cd ~
ls -la node_exporter-*.tar.gz

# Extraction
TARBALL=$(ls node_exporter-*.linux-amd64.tar.gz)
tar -xzf "$TARBALL"

# Récupère le nom exact du dossier extrait (fiable, pas de wildcard hasardeux)
EXTRACTDIR=$(tar -tzf "$TARBALL" | head -1 | cut -f1 -d"/")
echo ">>> Dossier extrait : $EXTRACTDIR"
ls -l "$EXTRACTDIR"

# Création utilisateur (affiche l'erreur si ce n'est pas juste "déjà existant")
sudo id node_exporter || sudo useradd -d /usr/share/node_exporter -s /bin/false node_exporter

# Déploiement du binaire avec vérification immédiate
sudo mkdir -p /usr/share/node_exporter
sudo mv -v "$EXTRACTDIR"/node_exporter /usr/share/node_exporter/
echo ">>> Vérification du binaire déployé :"
ls -l /usr/share/node_exporter/

sudo chown -R node_exporter:node_exporter /usr/share/node_exporter
sudo chmod 755 /usr/share/node_exporter/node_exporter

# Correction SELinux (au cas où, ne casse rien si désactivé)
sudo restorecon -Rv /usr/share/node_exporter/

# Service systemd
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
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

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sleep 2
echo ">>> Statut du service :"
systemctl status node_exporter --no-pager

# Firewall
sudo firewall-cmd --permanent --add-port=9100/tcp
sudo firewall-cmd --reload

# Test final
curl -s http://localhost:9100/metrics | head -5
