#!/bin/bash
# Installation process-exporter - reutilise le compte systeme node_exporter existant
# A executer avec sudo. Le binaire doit etre recupere au prealable (machine avec internet)
# depuis https://github.com/ncabatoff/process-exporter/releases (verifier la derniere version)
# puis transfere par scp, comme pour lmutil/flexlm_exporter.

set -e

fail() { echo "ERREUR: $1" >&2; exit 1; }

ARCHIVE="$1"   # ex: process-exporter-0.8.5.linux-amd64.tar.gz (a adapter selon version telechargee)
[ -z "$ARCHIVE" ] && fail "Usage: $0 <archive.tar.gz>"
[ -f "$ARCHIVE" ] || fail "Archive introuvable: $ARCHIVE"

INSTALL_DIR="/usr/share/process_exporter"
CONFIG_DIR="/etc/process_exporter"

# Verifie que le compte node_exporter existe deja (ne PAS en creer un nouveau)
id node_exporter >/dev/null 2>&1 || fail "Le compte systeme 'node_exporter' n'existe pas sur cette machine - installer node_exporter d'abord, ou adapter ce script pour reutiliser un autre compte de service deja approuve."

EXTRACT_DIR=$(tar -tzf "$ARCHIVE" | head -1 | cut -f1 -d"/")
[ -z "$EXTRACT_DIR" ] && fail "Impossible de determiner le dossier d'extraction"

TMPDIR=$(mktemp -d)
tar -xzf "$ARCHIVE" -C "$TMPDIR" || fail "Extraction echouee"

sudo mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
sudo cp "$TMPDIR/$EXTRACT_DIR/process-exporter" "$INSTALL_DIR/process-exporter" || fail "Copie du binaire echouee"
sudo chown node_exporter:node_exporter "$INSTALL_DIR/process-exporter"
sudo chmod 755 "$INSTALL_DIR/process-exporter"
sudo restorecon -Rv "$INSTALL_DIR/" || true

# Capacites Linux ciblees - permet de lire les /proc/[pid] d'autres utilisateurs
# SANS lancer le process en root et SANS creer de nouveau compte
sudo setcap cap_sys_ptrace,cap_dac_read_search+ep "$INSTALL_DIR/process-exporter" \
  || fail "setcap echoue - verifier que libcap est installe (yum install libcap)"

# Config: groupe par ExeBase (nom binaire complet, PAS Comm qui est tronque a 15 caracteres
# par le noyau Linux) + Username -> donne process + utilisateur en un seul label groupname
sudo tee "$CONFIG_DIR/config.yml" > /dev/null << 'EOF'
process_names:
  - name: "{{.ExeBase}}:{{.Username}}"
    cmdline:
    - '.+'
EOF

sudo tee /etc/systemd/system/process_exporter.service > /dev/null << 'EOF'
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

sudo systemctl daemon-reload
sudo systemctl enable --now process_exporter

# Firewall - meme port a ouvrir sur toutes les machines pour le scrape Prometheus
sudo firewall-cmd --permanent --add-port=9256/tcp
sudo firewall-cmd --reload

rm -rf "$TMPDIR"

echo "OK - verification :"
sleep 2
curl -s localhost:9256/metrics | grep namedprocess_namegroup_cpu | head -5
echo ""
echo "Si la liste ci-dessus est vide malgre un status actif, verifier hidepid (findmnt /proc)"
echo "et tester en root temporairement pour comparer:"
echo "  sudo -u node_exporter /usr/share/process_exporter/process-exporter --config.path /etc/process_exporter/config.yml --web.listen-address=:9257 &"
echo "  curl -s localhost:9257/metrics | grep namedprocess_namegroup_cpu | wc -l"
