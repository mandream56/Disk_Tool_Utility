#!/bin/bash

LOG_FILE="$HOME/disk_tool.log"
REPORT_DIR="$HOME/disk_tool_reports"
TMP_MOUNT="/mnt/img_mount"
mkdir -p "$REPORT_DIR" "$TMP_MOUNT"
REQUIRED_TOOLS=(lsblk dd losetup mount umount parted fdisk truncate grep awk xargs sudo yad gzip sha256sum cmp enscript ps2pdf xdg-open gnuplot tail appimagetool wget)

ICON_PATH="/usr/share/icons/gnome/48x48/devices/drive-harddisk.png"
CHAT_GIF="$HOME/.local/share/disk_tool/chat_pote.gif"

function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

function cleanup_temp() {
    sudo umount "$TMP_MOUNT" 2>/dev/null
    sudo losetup -D 2>/dev/null
    rm -rf "$TMP_MOUNT"/*
    log "Nettoyage des fichiers temporaires terminé."
}

trap cleanup_temp EXIT

function generate_pdf_report() {
    report_txt="$REPORT_DIR/report_$(date +%Y%m%d_%H%M%S).txt"
    report_pdf="${report_txt%.txt}.pdf"
    echo "--- Rapport Disk Tool ---" > "$report_txt"
    echo "Date : $(date)" >> "$report_txt"
    echo "Machine : $(hostname)" >> "$report_txt"
    echo "Utilisateur : $USER" >> "$report_txt"
    echo -e "
Dernières lignes du journal :" >> "$report_txt"
    tail -n 20 "$LOG_FILE" >> "$report_txt"
    enscript "$report_txt" -o - | ps2pdf - "$report_pdf"
    xdg-open "$report_pdf" &
}

function detect_system_partition() {
    SYSTEM_PART=$(lsblk -no MOUNTPOINT,NAME | grep ' /$' | awk '{print $2}')
    SYSTEM_DEV="/dev/$SYSTEM_PART"
    log "Partition système détectée : $SYSTEM_DEV"
    yad --info --image="$ICON_PATH" --text="Partition système détectée : $SYSTEM_DEV"
}

function check_tools() {
    missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        yad --info --image="$ICON_PATH" --text="Installation des outils manquants : ${missing[*]}"
        if command -v apt &>/dev/null; then
            sudo apt update
            sudo apt install -y "${missing[@]}"
        else
            yad --error --text="Gestionnaire de paquets non supporté. Abandon."
            exit 1
        fi
    fi

    if [ ! -f "$CHAT_GIF" ]; then
        mkdir -p "$(dirname "$CHAT_GIF")"
        wget -O "$CHAT_GIF" "https://media.tenor.com/XG3qK8v8cmUAAAAC/puss-in-boots-eyes.gif" 2>/dev/null
    fi

    detect_system_partition
}

function show_realtime_log() {
    ( tail -f "$LOG_FILE" & echo $! > /tmp/logtail.pid ) | yad --text-info --title="Log en temps réel" --width=900 --height=500 --tail --center
    kill $(cat /tmp/logtail.pid)
}

function generate_stats_plot() {
    stats_file="$REPORT_DIR/stats.dat"
    grep "Clonage de" "$LOG_FILE" | awk '{print $1, $2, $(NF)}' > "$stats_file"
    gnuplot -persist <<-EOF
        set title "Historique des opérations de clonage"
        set xlabel "Date"
        set xdata time
        set timefmt "%Y-%m-%d"
        set format x "%d/%m"
        set ylabel "Nom du disque/image"
        set style data linespoints
        set terminal pngcairo size 800,400
        set output "$REPORT_DIR/stats.png"
        plot "$stats_file" using 0:xtic(2) title 'Clonages'
EOF
    yad --image="$REPORT_DIR/stats.png" --title="Statistiques" --button=gtk-ok --width=820 --height=450
}

function verify_image_integrity() {
    image_file=$(yad --file --title="Sélectionner une image à vérifier")
    if [[ -f "$image_file" ]]; then
        log "Vérification de l'image : $image_file"
        checksum_file="$image_file.sha256"
        if [[ -f "$checksum_file" ]]; then
            sha256sum -c "$checksum_file" | tee -a "$LOG_FILE"
        else
            sha256sum "$image_file" | tee "$checksum_file" "$LOG_FILE"
        fi
    fi
}

function clone_disk() {
    src=$(lsblk -dpno NAME,SIZE,TYPE | grep disk | yad --list --title="Sélectionnez le disque source" --column="Disque" --column="Taille" --column="Type" --width=700 --height=300 --separator=" " --multiple --button=gtk-ok:0 --button=gtk-cancel:1 | cut -d'|' -f1)
    dest=$(yad --file-selection --save --title="Nom du fichier image de destination")
    if [[ -n "$src" && -n "$dest" ]]; then
        log "Clonage de $src vers $dest"
        yad --progress --pulsate --auto-close --title="Clonage en cours" --text="Clonage de $src vers $dest..." &
        dd if="$src" of="$dest" bs=4M status=progress conv=sync,noerror && sync
        sha256sum "$dest" > "$dest.sha256"
        log "Clonage terminé. Image : $dest"
        verify_image_integrity "$dest"
    fi
}

function restore_image() {
    img=$(yad --file-selection --title="Sélectionnez l'image à restaurer")
    tgt=$(lsblk -dpno NAME,SIZE,TYPE | grep disk | yad --list --title="Sélectionnez le disque cible" --column="Disque" --column="Taille" --column="Type" --width=700 --height=300 --separator=" " --multiple --button=gtk-ok:0 --button=gtk-cancel:1 | cut -d'|' -f1)
    if [[ -n "$img" && -n "$tgt" ]]; then
        log "Restauration de $img vers $tgt"
        yad --progress --pulsate --auto-close --title="Restauration en cours" --text="Restauration de l'image..." &
        dd if="$img" of="$tgt" bs=4M status=progress conv=sync,noerror && sync
        sha256sum -c "$img.sha256" | tee -a "$LOG_FILE"
        log "Restauration terminée."
    fi
}

function reduce_image() {
    img=$(yad --file-selection --title="Sélectionnez l'image à réduire")
    loopdev=$(sudo losetup --show -fP "$img")
    part=$(ls ${loopdev}p* 2>/dev/null | tail -n 1)
    if [[ -z "$part" ]]; then
        yad --error --text="Impossible de détecter la partition."
        sudo losetup -d "$loopdev"
        return
    fi
    sudo mount "$part" "$TMP_MOUNT"
    block=$(df --block-size=512 "$TMP_MOUNT" | awk 'NR==2 {print $3}')
    sudo umount "$TMP_MOUNT"
    sudo losetup -d "$loopdev"
    last_block=$(yad --entry --title="Dernier bloc" --text="Bloc actuel utilisé : $block
Entrez manuellement le dernier bloc à conserver (ou laissez vide pour utiliser la valeur actuelle) :")
    [[ -z "$last_block" ]] && last_block=$block
    out_img=$(yad --file-selection --save --title="Enregistrer l'image réduite")
    if [[ -n "$out_img" ]]; then
        truncate -s $((last_block * 512)) "$img"
        gzip -c "$img" > "$out_img.gz"
        log "Image réduite et compressée enregistrée : $out_img.gz"
    fi
}

function show_about() {
    yad --image="$CHAT_GIF" --title="À propos" --text="<b>Disk Tool</b>
Créé le : $(date -r "$0" +"%d/%m/%Y")

Développé par <b>ChatGPT</b>
Aidée par Cédric qui n'a fait que lui poser des questions pour améliorer le script." --width=500 --height=450 --center --button=gtk-ok
}

function show_dashboard() {
    while true; do
        CHOICE=$(yad --window-icon="$ICON_PATH" --width=400 --height=300 --center             --title="Disk Tool" --form             --image="$ICON_PATH" --separator=" " --button=gtk-quit:1             --button="🛠 Cloner un disque":2             --button="🧩 Restaurer une image":3             --button="📦 Réduire une image":4             --button="📑 Rapport PDF":5             --button="📊 Voir statistiques":6             --button="🔍 Logs en direct":7             --button="🔁 Vérification d'image":8             --button="ℹ️ À propos":9)

        case $? in
            1) exit 0;;
            2) clone_disk;;
            3) restore_image;;
            4) reduce_image;;
            5) generate_pdf_report;;
            6) generate_stats_plot;;
            7) show_realtime_log;;
            8) verify_image_integrity;;
            9) show_about;;
        esac
    done
}

check_tools
show_dashboard
