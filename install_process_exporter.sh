#!/bin/bash
# ==============================================================================
# Installation complete : process-exporter + resolution des utilisateurs AD
# A copier dans le home de la machine avec l'archive process-exporter, puis :
#   chmod +x install_complet.sh
#   sudo ./install_complet.sh process-exporter-0.8.7.linux-amd64.tar.gz
#
# Prerequis : node_exporter doit deja etre installe et fonctionnel sur la machine
# (on reutilise son compte systeme, aucun nouveau compte cree).
# ==============================================================================

set -euo pipefail

fail() { echo "ERREUR: $1" >&2; exit 1; }
step() { echo ""; echo "=== $1 ==="; }

[ "$(id -u)" -eq 0 ] || fail "Ce script doit etre lance avec sudo/root."

ARCHIVE="${1:-}"
[ -z "$ARCHIVE" ] && fail "Usage: $0 <archive_process-exporter.tar.gz>"
[ -f "$ARCHIVE" ] || fail "Archive introuvable: $ARCHIVE"

id node_exporter >/dev/null 2>&1 || fail "Le compte systeme 'node_exporter' n'existe pas - installer node_exporter d'abord."

INSTALL_DIR="/usr/share/process_exporter"
CONFIG_DIR="/etc/process_exporter"
TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"
UID_SCRIPT="/usr/local/bin/generate_uid_map.sh"

# ------------------------------------------------------------------------------
step "1/8 - Extraction et installation du binaire process-exporter"
# ------------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
tar -xzf "$ARCHIVE" -C "$TMPDIR" || fail "Extraction de l'archive echouee"

# Recherche robuste du binaire (independant de la structure interne de l'archive,
# contrairement a la premiere version du script qui devinait le dossier racine)
BINARY_PATH=$(find "$TMPDIR" -type f -name "process-exporter" | head -1)
[ -z "$BINARY_PATH" ] && fail "Binaire 'process-exporter' introuvable dans l'archive"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
cp "$BINARY_PATH" "$INSTALL_DIR/process-exporter"
chown -R node_exporter:node_exporter "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR/process-exporter"
chmod 755 "$CONFIG_DIR"
restorecon -Rv "$INSTALL_DIR" 2>/dev/null || true
rm -rf "$TMPDIR"
echo "OK - binaire installe dans $INSTALL_DIR"

# ------------------------------------------------------------------------------
step "2/8 - Configuration process-exporter (groupement process + utilisateur)"
# ------------------------------------------------------------------------------
cat > "$CONFIG_DIR/config.yml" << 'EOF'
process_names:
  - name: "{{.ExeBase}}:{{.Username}}"
    cmdline:
    - '.+'
EOF
chmod 644 "$CONFIG_DIR/config.yml"
echo "OK - config ecrite dans $CONFIG_DIR/config.yml"

# ------------------------------------------------------------------------------
step "3/8 - Service systemd process_exporter"
# ------------------------------------------------------------------------------
cat > /etc/systemd/system/process_exporter.service << 'EOF'
[Unit]
Description=Process Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/share/process_exporter/process-exporter \
  --config.path /etc/process_exporter/config.yml \
  --web.listen-address=:9256
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------------------------
step "4/8 - Firewall (port 9256, scrape Prometheus)"
# ------------------------------------------------------------------------------
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=9256/tcp
  firewall-cmd --reload
  echo "OK - port 9256/tcp ouvert"
else
  echo "firewall-cmd absent, a verifier manuellement si un firewall est actif"
fi

# ------------------------------------------------------------------------------
step "5/8 - Script de resolution UID -> utilisateur AD (via getent/SSSD)"
# ------------------------------------------------------------------------------
cat > "$UID_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
# Lookup CIBLE par UID (pas d'enumeration globale - SSSD n'enumere pas l'AD par defaut)
set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="$OUTPUT_DIR/uid_username_map.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"

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

mv -f "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
SCRIPT_EOF
chmod 755 "$UID_SCRIPT"
echo "OK - script ecrit dans $UID_SCRIPT"

# ------------------------------------------------------------------------------
step "6/8 - Dossier textfile_collector (permissions completes, parent inclus)"
# ------------------------------------------------------------------------------
# Le dossier parent /var/lib/node_exporter est souvent cree en 750 root:root par
# l'installation initiale de node_exporter - il faut le rendre traversable aussi,
# sinon node_exporter ne peut meme pas atteindre le sous-dossier.
mkdir -p "$TEXTFILE_DIR"
chmod 755 /var/lib/node_exporter
chown node_exporter:node_exporter "$TEXTFILE_DIR"
chmod 755 "$TEXTFILE_DIR"
echo "OK - $TEXTFILE_DIR pret (parent et dossier en 755)"

# ------------------------------------------------------------------------------
step "7/8 - Activation du textfile collector sur node_exporter (sans ecraser les flags existants)"
# ------------------------------------------------------------------------------
[ -f "$NODE_EXPORTER_SERVICE" ] || fail "$NODE_EXPORTER_SERVICE introuvable"

if grep -q "collector.textfile.directory" "$NODE_EXPORTER_SERVICE"; then
  echo "Deja configure, on ne touche pas au service (evite les doublons de flag)."
else
  sed -i "/^ExecStart=/ s|\$| --collector.textfile.directory=${TEXTFILE_DIR}|" "$NODE_EXPORTER_SERVICE"
  echo "OK - flag ajoute a la suite des flags existants:"
  grep ExecStart "$NODE_EXPORTER_SERVICE"
fi

# ------------------------------------------------------------------------------
step "8/8 - Cron (execution sous l'utilisateur node_exporter, pas root)"
# ------------------------------------------------------------------------------
cat > /etc/cron.d/uid_username_map << EOF
*/10 * * * * node_exporter $UID_SCRIPT
EOF
echo "OK - cron programme toutes les 10 minutes"

# ------------------------------------------------------------------------------
step "Demarrage / redemarrage des services"
# ------------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now process_exporter
sleep 3

sudo -u node_exporter "$UID_SCRIPT"
systemctl restart node_exporter
sleep 2

# ------------------------------------------------------------------------------
step "VERIFICATION FINALE"
# ------------------------------------------------------------------------------
echo ""
echo "--- process_exporter ---"
systemctl is-active process_exporter
curl -s localhost:9256/metrics | grep -c namedprocess_namegroup_cpu_seconds_total || true

echo ""
echo "--- node_exporter (textfile) ---"
systemctl is-active node_exporter
echo "Correspondances UID trouvees :"
curl -s localhost:9100/metrics | grep node_uid_username || echo "(aucune pour le moment - normal si aucun process AD non-resolu n'est actif la maintenant)"

echo ""
echo "=== TERMINE ==="
echo "Si les deux services sont 'active' et que le curl process_exporter renvoie un nombre > 0,"
echo "il ne reste plus qu'a ajouter cette machine au job 'process_exporter' dans prometheus.yml :"
echo "  - '$(hostname -f):9256'"
echo "puis promtool check config && systemctl reload prometheus (sur saxfrc0154)."
