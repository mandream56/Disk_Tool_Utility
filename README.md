# Disk Tool

**Disk Tool** est un utilitaire Bash complet avec interface graphique YAD pour :
- Clonage/restauration de disques avec `dd`
- Réduction d’image disque
- Vérification d’intégrité avec SHA256
- Visualisation temps réel des logs
- Génération de rapports PDF
- Suivi graphique des statistiques avec Gnuplot
- Interface graphique complète avec animations et icônes
- Support AppImage à venir

## Lancement

```bash
bash disk_tool.sh
```

## Dépendances

Le script installe automatiquement les outils suivants si non présents :
- `yad`, `dd`, `lsblk`, `losetup`, `mount`, `umount`, `parted`, `truncate`, `awk`, `gzip`, `sha256sum`, `cmp`
- `enscript`, `ps2pdf`, `xdg-open`, `gnuplot`

## Auteurs

Développé par **ChatGPT**  
Avec l’aide précieuse (en questions 😄) de **Cédric**

![Potté](assets/chat_pote.gif)

## Licence

Libre d’utilisation et de modification.
