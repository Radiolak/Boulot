#!/bin/bash
# Genere la correspondance UID -> nom d'utilisateur au format Prometheus textfile.
# IMPORTANT: on NE fait PAS de "getent passwd" global (SSSD n'enumere pas l'AD par defaut,
# donc ca ne renverrait que les comptes locaux/deja en cache).
# On fait un lookup CIBLE par UID pour chaque UID numerique non resolu vu dans process-exporter -
# un lookup individuel declenche toujours une vraie requete SSSD et fonctionne.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="$OUTPUT_DIR/uid_username_map.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"

# Recupere la liste des UID numeriques actuellement non resolus par process-exporter
# (partie apres le dernier ":" dans groupname, quand c'est purement numerique)
UIDS=$(curl -s localhost:9256/metrics 2>/dev/null \
  | grep -oP 'groupname="[^"]*:\K[0-9]+(?=")' \
  | sort -u)

{
  echo "# HELP node_uid_username Correspondance UID vers nom d'utilisateur (lookup cible via getent/SSSD)"
  echo "# TYPE node_uid_username gauge"
  for uid in $UIDS; do
    entry=$(getent passwd "$uid" 2>/dev/null || true)
    if [ -n "$entry" ]; then
      user=$(echo "$entry" | cut -d: -f1)
      user_escaped=$(printf '%s' "$user" | sed 's/"/\\"/g')
      echo "node_uid_username{uid=\"$uid\",username=\"$user_escaped\"} 1"
    fi
  done
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"