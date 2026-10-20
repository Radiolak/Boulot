#!/bin/bash
# Deploiement complet BogoMips - idempotent, sans danger a relancer plusieurs fois
# meme si le textfile collector est deja configure (travail UID precedent).
#
# Usage : sudo ./install_bogomips.sh

set -euo pipefail

fail() { echo "ERREUR: $1" >&2; exit 1; }
step() { echo ""; echo "=== $1 ==="; }

[ "$(id -u)" -eq 0 ] || fail "Ce script doit etre lance avec sudo/root."

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
NODE_EXPORTER_SERVICE="/etc/systemd/system/node_exporter.service"
BOGOMIPS_SCRIPT="/usr/local/bin/generate_bogomips.sh"

id node_exporter >/dev/null 2>&1 || fail "Le compte systeme 'node_exporter' n'existe pas sur cette machine."

# ------------------------------------------------------------------------------
step "1/6 - Ecriture du script generate_bogomips.sh"
# ------------------------------------------------------------------------------
cat > "$BOGOMIPS_SCRIPT" << 'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

OUTPUT_DIR="/var/lib/node_exporter/textfile_collector"
OUTPUT_FILE="$OUTPUT_DIR/cpu_bogomips.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"

mkdir -p "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR" 2>/dev/null || true

BOGOMIPS_VALUES=$(grep -i '^bogomips' /proc/cpuinfo | awk -F: '{print $2}' | tr -d ' ')

if [ -z "$BOGOMIPS_VALUES" ]; then
  echo "Aucune valeur bogomips trouvee dans /proc/cpuinfo - abandon."
  exit 1
fi

TOTAL=$(echo "$BOGOMIPS_VALUES" | awk '{sum+=$1} END {printf "%.2f", sum}')
AVG=$(echo "$BOGOMIPS_VALUES" | awk '{sum+=$1; n++} END {printf "%.2f", sum/n}')

{
  echo "# HELP node_cpu_bogomips_total Somme des BogoMips de tous les coeurs logiques"
  echo "# TYPE node_cpu_bogomips_total gauge"
  echo "node_cpu_bogomips_total $TOTAL"
  echo "# HELP node_cpu_bogomips_avg BogoMips moyen par coeur logique"
  echo "# TYPE node_cpu_bogomips_avg gauge"
  echo "node_cpu_bogomips_avg $AVG"
} > "$TMP_FILE"

mv -f "$TMP_FILE" "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
SCRIPT_EOF
chmod 755 "$BOGOMIPS_SCRIPT"
echo "OK"

# ------------------------------------------------------------------------------
step "2/6 - Dossier textfile_collector (parent + lui-meme, permissions completes)"
# ------------------------------------------------------------------------------
mkdir -p "$TEXTFILE_DIR"
chmod 755 /var/lib/node_exporter
chown node_exporter:node_exporter "$TEXTFILE_DIR"
chmod 755 "$TEXTFILE_DIR"
echo "OK"

# ------------------------------------------------------------------------------
step "3/6 - Flag --collector.textfile.directory sur node_exporter (sans doublon)"
# ------------------------------------------------------------------------------
[ -f "$NODE_EXPORTER_SERVICE" ] || fail "$NODE_EXPORTER_SERVICE introuvable"

if grep -q "collector.textfile.directory" "$NODE_EXPORTER_SERVICE"; then
  echo "Flag deja present dans le fichier de service."
else
  sed -i "/^ExecStart=/ s|\$| --collector.textfile.directory=${TEXTFILE_DIR}|" "$NODE_EXPORTER_SERVICE"
  echo "Flag ajoute:"
  grep ExecStart "$NODE_EXPORTER_SERVICE"
fi

# On redemarre TOUJOURS, meme si le flag etait deja dans le fichier :
# un fichier modifie sans redemarrage depuis ne change rien au process en cours.
RESTART_NEEDED=true

# ------------------------------------------------------------------------------
step "4/6 - Cron (toutes les 15 minutes, sous l'utilisateur node_exporter)"
# ------------------------------------------------------------------------------
cat > /etc/cron.d/cpu_bogomips << EOF
*/15 * * * * node_exporter $BOGOMIPS_SCRIPT
EOF
echo "OK"

# ------------------------------------------------------------------------------
step "5/6 - Generation immediate + redemarrage si necessaire"
# ------------------------------------------------------------------------------
sudo -u node_exporter "$BOGOMIPS_SCRIPT"

if [ "$RESTART_NEEDED" = true ]; then
  systemctl daemon-reload
  systemctl restart node_exporter
  sleep 2
fi
echo "OK"

# ------------------------------------------------------------------------------
step "6/6 - VERIFICATION"
# ------------------------------------------------------------------------------
echo ""
cat "$TEXTFILE_DIR/cpu_bogomips.prom"
echo ""
echo "--- Depuis node_exporter ---"
curl -s localhost:9100/metrics | grep bogomips || echo "RIEN - probleme, verifier les etapes ci-dessus"
