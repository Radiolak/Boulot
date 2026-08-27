#!/bin/bash
# Genere la correspondance UID -> nom d'utilisateur au format Prometheus textfile.
# getent passe par NSS/SSSD correctement (contrairement au binaire Go statique de process-exporter),
# donc resout aussi bien les comptes locaux que les comptes AD.

set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="$OUTPUT_DIR/uid_username_map.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"

{
  echo "# HELP node_uid_username Correspondance UID vers nom d'utilisateur (source: getent passwd)"
  echo "# TYPE node_uid_username gauge"
  getent passwd | awk -F: '{
    uid=$3; user=$1;
    gsub(/"/, "\\\"", user);
    print "node_uid_username{uid=\"" uid "\",username=\"" user "\"} 1"
  }'
} > "$TMP_FILE"

# Ecriture atomique - evite que node_exporter lise un fichier a moitie ecrit
mv "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE" 