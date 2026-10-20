#!/bin/bash

fail() {
    echo "❌ ERREUR à l'étape: $1"
    exit 1
}

# Doit être lancé depuis le répertoire où grafana-12.3.11 a été extrait
SRC="$(pwd)/grafana-12.3.11"
[ -d "$SRC" ] || fail "dossier grafana-12.3.11 introuvable dans $(pwd)"

echo ">>> Vérification de la structure de la nouvelle version"
[ -d "$SRC/bin" ] || fail "dossier bin/ manquant dans l'archive"
[ -d "$SRC/public" ] || fail "dossier public/ manquant dans l'archive"
[ -d "$SRC/conf" ] || fail "dossier conf/ manquant dans l'archive"

# Détection du nom du binaire (grafana-server sur anciennes versions, grafana sur récentes)
if [ -f "$SRC/bin/grafana" ]; then
    BINNAME="grafana"
    SUBCMD="server"
elif [ -f "$SRC/bin/grafana-server" ]; then
    BINNAME="grafana-server"
    SUBCMD=""
else
    fail "aucun binaire grafana trouvé dans $SRC/bin"
fi
echo "Binaire détecté : $BINNAME"

sudo -v || fail "authentification sudo"

echo ">>> Arrêt du service actuel"
sudo systemctl stop grafana-server 2>/dev/null

echo ">>> Sauvegarde de la base de données actuelle (dashboards/datasources)"
if [ -f /var/lib/grafana/grafana.db ]; then
    sudo cp /var/lib/grafana/grafana.db /var/lib/grafana/grafana.db.backup_$(date +%Y%m%d_%H%M%S) \
        || fail "sauvegarde grafana.db"
fi

echo ">>> Sauvegarde de la config actuelle"
sudo cp -r /etc/grafana /etc/grafana.backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null

echo ">>> Suppression complète des anciens binaires/public/conf (pas touche à /etc/grafana ni /var/lib/grafana)"
sudo rm -rf /usr/share/grafana || fail "suppression /usr/share/grafana"
sudo rm -f /usr/sbin/grafana-server

echo ">>> Recréation de la structure et copie de la nouvelle version"
sudo mkdir -p /usr/share/grafana || fail "création /usr/share/grafana"
sudo cp -r "$SRC/bin" /usr/share/grafana/ || fail "copie bin/"
sudo cp -r "$SRC/public" /usr/share/grafana/ || fail "copie public/"
sudo cp -r "$SRC/conf" /usr/share/grafana/ || fail "copie conf/"

echo ">>> Vérification utilisateur système grafana"
sudo id grafana &>/dev/null || sudo useradd -r -s /bin/false grafana || fail "création utilisateur grafana"

echo ">>> Droits"
sudo chown -R grafana:grafana /usr/share/grafana || fail "chown /usr/share/grafana"
sudo chmod 755 "/usr/share/grafana/bin/$BINNAME" || fail "chmod binaire"
sudo restorecon -Rv /usr/share/grafana &>/dev/null

echo ">>> Vérification /etc/grafana et /var/lib/grafana (créés si absents)"
sudo mkdir -p /etc/grafana /var/lib/grafana /var/log/grafana
if [ ! -f /etc/grafana/grafana.ini ]; then
    sudo cp /usr/share/grafana/conf/sample.ini /etc/grafana/grafana.ini || fail "création grafana.ini par défaut"
fi
sudo chown -R grafana:grafana /etc/grafana /var/lib/grafana /var/log/grafana

echo ">>> Lien symbolique /usr/sbin/grafana-server"
sudo ln -sf "/usr/share/grafana/bin/$BINNAME" /usr/sbin/grafana-server || fail "création lien symbolique"

echo ">>> Recréation du fichier service systemd"
if [ "$BINNAME" = "grafana" ]; then
    EXEC_LINE="ExecStart=/usr/share/grafana/bin/grafana server --config=\${CONF_FILE} --pidfile=\${PID_FILE_DIR}/grafana-server.pid --homepath=/usr/share/grafana cfg:default.paths.logs=\${LOG_DIR} cfg:default.paths.data=\${DATA_DIR} cfg:default.paths.plugins=\${PLUGINS_DIR} cfg:default.paths.provisioning=\${PROVISIONING_CFG_DIR}"
else
    EXEC_LINE="ExecStart=/usr/sbin/grafana-server --config=\${CONF_FILE} --pidfile=\${PID_FILE_DIR}/grafana-server.pid cfg:default.paths.logs=\${LOG_DIR} cfg:default.paths.data=\${DATA_DIR} cfg:default.paths.plugins=\${PLUGINS_DIR} cfg:default.paths.provisioning=\${PROVISIONING_CFG_DIR}"
fi

sudo tee /etc/systemd/system/grafana-server.service > /dev/null <<EOF || fail "création fichier service"
[Unit]
Description=Grafana instance
Documentation=http://docs.grafana.org
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/default/grafana-server
User=grafana
Group=grafana
Type=simple
Restart=on-failure
WorkingDirectory=/usr/share/grafana
RuntimeDirectory=grafana
RuntimeDirectoryMode=0750
$EXEC_LINE
LimitNOFILE=10000
TimeoutStopSec=20
UMask=0027

[Install]
WantedBy=multi-user.target
EOF

echo ">>> Vérification /etc/default/grafana-server (variables d'environnement)"
if [ ! -f /etc/default/grafana-server ]; then
sudo tee /etc/default/grafana-server > /dev/null <<'EOF'
GRAFANA_USER=grafana
GRAFANA_GROUP=grafana
GRAFANA_HOME=/usr/share/grafana
LOG_DIR=/var/log/grafana
DATA_DIR=/var/lib/grafana
MAX_OPEN_FILES=10000
CONF_DIR=/etc/grafana
CONF_FILE=/etc/grafana/grafana.ini
RESTART_ON_UPGRADE=true
PLUGINS_DIR=/var/lib/grafana/plugins
PROVISIONING_CFG_DIR=/etc/grafana/provisioning
PID_FILE_DIR=/var/run/grafana
EOF
fi

echo ">>> Désactivation du téléchargement automatique de plugins (pas d'accès internet)"
if ! grep -q "preinstall_disabled" /etc/grafana/grafana.ini 2>/dev/null; then
    echo -e "\n[plugins]\npreinstall_disabled = true" | sudo tee -a /etc/grafana/grafana.ini > /dev/null
fi

echo ">>> Démarrage du service"
sudo systemctl daemon-reload || fail "daemon-reload"
sudo systemctl enable grafana-server || fail "enable service"
sudo systemctl start grafana-server || fail "démarrage service"

sleep 3

sudo systemctl is-active --quiet grafana-server || fail "service pas actif (voir: sudo journalctl -u grafana-server -n 50 --no-pager)"

echo "✅ Grafana $BINNAME opérationnel"
curl -s http://localhost:3000/api/health
