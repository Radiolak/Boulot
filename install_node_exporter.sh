#!/bin/bash

fail() {
    echo "❌ ERREUR à l'étape: $1"
    exit 1
}

sudo -v || fail "authentification sudo"

TARBALL=$(ls ./node_exporter-*.linux-amd64.tar.gz 2>/dev/null) || fail "tar.gz introuvable dans le répertoire courant ($(pwd))"

tar -xzf "$TARBALL" || fail "extraction tar.gz"
EXTRACTDIR=$(tar -tzf "$TARBALL" | head -1 | cut -f1 -d"/") || fail "lecture nom dossier extrait"

if ! sudo id node_exporter &>/dev/null; then
    sudo useradd -d /usr/share/node_exporter -s /bin/false node_exporter || fail "création utilisateur node_exporter"
fi

sudo mkdir -p /usr/share/node_exporter || fail "création /usr/share/node_exporter"
sudo cp "$EXTRACTDIR/node_exporter" /usr/share/node_exporter/node_exporter || fail "copie du binaire"

# Vérifie que c'est bien un fichier, pas un dossier
sudo test -f /usr/share/node_exporter/node_exporter || fail "binaire absent après copie (vérifier structure de dossiers)"

sudo chown node_exporter:node_exporter /usr/share/node_exporter/node_exporter || fail "chown binaire"
sudo chmod 755 /usr/share/node_exporter/node_exporter || fail "chmod binaire"
sudo restorecon -Rv /usr/share/node_exporter/ &>/dev/null

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF' || fail "création fichier service"
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/share/node_exporter/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload || fail "daemon-reload"
sudo systemctl enable --now node_exporter || fail "activation/démarrage du service"

sleep 2

sudo systemctl is-active --quiet node_exporter || fail "service pas actif après démarrage (voir: systemctl status node_exporter)"

sudo firewall-cmd --permanent --add-port=9100/tcp &>/dev/null
sudo firewall-cmd --reload || fail "reload firewall"

RESULT=$(curl -s http://localhost:9100/metrics | head -1)
if [[ -z "$RESULT" ]]; then
    fail "curl metrics - aucune réponse"
fi

echo "✅ node_exporter opérationnel"
echo "$RESULT"
