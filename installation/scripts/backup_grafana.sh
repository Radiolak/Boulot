#!/bin/bash
# ==============================================================================
# Sauvegarde de Grafana : base de données (SQLite) + configuration
#
# Ce qui est sauvegardé :
#   - /var/lib/grafana/grafana.db : dashboards, dossiers, sources de données,
#     utilisateurs, droits, préférences, alertes Grafana
#   - /etc/grafana : grafana.ini et provisioning
#
# La copie de la base se fait à chaud (commande .backup de SQLite) :
# pas besoin d'arrêter Grafana.
#
# Usage : sudo /usr/local/sbin/backup_grafana.sh
# ==============================================================================
set -euo pipefail

DB=/var/lib/grafana/grafana.db
CONF_DIR=/etc/grafana
DEST=/var/backups/grafana        # dossier des sauvegardes sur le serveur
KEEP_DAYS=14                     # nombre de jours de sauvegardes gardées
COPY_TO=""                       # copie hors serveur (ex : partage NFS). Vide = pas de copie

TS=$(date +%Y%m%d_%H%M)
fail() { echo "ERREUR : $1" >&2; logger -t backup_grafana "ERREUR : $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "lancer le script avec sudo"
command -v sqlite3 >/dev/null || fail "sqlite3 absent (sudo dnf install sqlite)"
[ -f "$DB" ] || fail "$DB introuvable"

mkdir -p "$DEST"
chmod 700 "$DEST"   # grafana.ini contient des secrets : accès root uniquement

# 1. Base de données (copie cohérente même si Grafana écrit pendant la sauvegarde)
sqlite3 -cmd ".timeout 30000" "$DB" ".backup '$DEST/grafana_$TS.db'" || fail "copie de la base"
CHECK=$(sqlite3 "$DEST/grafana_$TS.db" "PRAGMA integrity_check;")
[ "$CHECK" = "ok" ] || fail "copie de la base corrompue ($CHECK)"
gzip -f "$DEST/grafana_$TS.db"

# 2. Configuration
tar -czf "$DEST/grafana-conf_$TS.tar.gz" -C / "${CONF_DIR#/}" || fail "copie de la configuration"

# 3. Copie hors serveur (optionnelle)
if [ -n "$COPY_TO" ]; then
    mkdir -p "$COPY_TO" || fail "dossier $COPY_TO inaccessible"
    cp -f "$DEST/grafana_$TS.db.gz" "$DEST/grafana-conf_$TS.tar.gz" "$COPY_TO/" || fail "copie vers $COPY_TO"
    find "$COPY_TO" -maxdepth 1 -name 'grafana*_*.gz' -mtime +"$KEEP_DAYS" -delete
fi

# 4. Suppression des sauvegardes trop anciennes
find "$DEST" -maxdepth 1 -name 'grafana*_*.gz' -mtime +"$KEEP_DAYS" -delete

MSG="OK : grafana_$TS.db.gz ($(du -h "$DEST/grafana_$TS.db.gz" | cut -f1)) + grafana-conf_$TS.tar.gz"
echo "$MSG"
logger -t backup_grafana "$MSG"
