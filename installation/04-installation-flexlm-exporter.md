# Installation flexlm_exporter - Documentation complète (v2)

Cette procédure part de zéro et intègre tous les pièges déjà rencontrés et résolus.
Testée et validée en conditions réelles sur `saxfrc0154`.

---

## Étape 0 — Récupérer le bon binaire

Sur https://github.com/mjtrangoni/flexlm_exporter/releases, prendre la dernière
version (v0.0.13), asset **linux_x86_64.tar.gz** (pas "Source code").

Transférer dans `~` via MobaXterm (panneau SFTP à gauche).

---

## Étape 1 — Récupérer lmutil

`lmutil` est le binaire propriétaire FlexNet qui interroge réellement les serveurs
de licences. L'exporter ne fait qu'exécuter ce binaire et parser sa sortie.

**Sur un serveur de licences (ex: smfidf5102, qui héberge les daemons lmgrd) :**
```bash
ssh smfidf5102
find /admin/flexlm -iname "lmutil" 2>/dev/null
```

Plusieurs résultats apparaîtront (un par version installée, ex: `11.14.x`,
`11.16.x`, `11.19.x`). **Prendre la version la plus récente disponible**
(FlexNet est rétrocompatible).

Rapatrier ce binaire vers la machine Prometheus (MobaXterm) dans `~`.

---

## Étape 2 — Installation des binaires

```bash
cd ~

# Extraction - vérifier le contenu avant de copier (le nom du dossier peut varier)
tar -xzf flexlm_exporter*.tar.gz
ls -la
find . -maxdepth 3 -iname "flexlm_exporter" -type f

sudo useradd -r -s /bin/false flexlm_exporter
sudo mkdir -p /usr/share/flexlm_exporter

# Adapter le chemin source selon ce que "find" a montré ci-dessus
sudo cp <chemin_trouvé>/flexlm_exporter /usr/share/flexlm_exporter/
sudo cp ~/lmutil /usr/share/flexlm_exporter/

sudo chown flexlm_exporter:flexlm_exporter /usr/share/flexlm_exporter/flexlm_exporter
sudo chown flexlm_exporter:flexlm_exporter /usr/share/flexlm_exporter/lmutil
sudo chmod 755 /usr/share/flexlm_exporter/flexlm_exporter
sudo chmod 755 /usr/share/flexlm_exporter/lmutil
sudo restorecon -Rv /usr/share/flexlm_exporter/
```

**Vérification :**
```bash
ls -la /usr/share/flexlm_exporter/
```
Les deux fichiers doivent afficher `-rwxr-xr-x` et appartenir à `flexlm_exporter:flexlm_exporter`.

---

## Étape 3 — ⚠️ Fix obligatoire sur RHEL 9 : interpréteur LSB manquant

`lmutil` est lié à un chargeur `/lib64/ld-lsb-x86-64.so.3`, hérité de la norme
Linux Standard Base. Ce paquet (`redhat-lsb-core`) **n'existe plus du tout sur
RHEL 9** (ni en dépôt officiel, ni ailleurs) — sans lui, `lmutil` refuse de
s'exécuter avec une erreur trompeuse `No such file or directory` (le fichier
existe bien, c'est son interpréteur qui manque).

**La solution : ce loader LSB est fonctionnellement identique au loader
standard glibc — un simple lien symbolique suffit, pas besoin de RPM.**

```bash
sudo ln -s /lib64/ld-linux-x86-64.so.2 /lib64/ld-lsb-x86-64.so.3
```

**Vérifier le nom EXACT du lien créé** (piège rencontré : `ld-linux` au lieu de
`ld-lsb` dans le nom du lien lui-même — un seul mot différent et ça ne fonctionne pas) :
```bash
ls -la /lib64/ld-lsb-x86-64.so.3
```
Doit afficher : `ld-lsb-x86-64.so.3 -> /lib64/ld-linux-x86-64.so.2`

**Test de validation :**
```bash
sudo /usr/share/flexlm_exporter/lmutil
```
Doit afficher l'aide/usage de `lmutil` (pas d'erreur).

📌 **À refaire sur chaque nouvelle machine** où `flexlm_exporter` sera installé —
ce n'est pas spécifique à `saxfrc0154`, c'est lié à RHEL 9 en général.

---

## Étape 4 — Test avec l'utilisateur dédié

```bash
sudo -u flexlm_exporter /usr/share/flexlm_exporter/lmutil lmstat -c 7102@phi -a
```

Doit afficher la liste des features Cam350 avec les utilisateurs connectés.
**Ce test doit réussir avant de continuer.**

---

## Étape 5 — Configuration (licenses.yml)

Liste reconstituée depuis l'outil PHP "License Server Status". **Hypothèse** :
les mêmes app/port apparaissant sur phi + khi + psi sont un triplet redondant
FlexLM (3 serveurs qui doivent s'accorder), regroupés en une entrée avec 3 hôtes
séparés par virgule. **À vérifier** — si ce sont en réalité 3 pools indépendants,
séparer en entrées distinctes.

```bash
sudo mkdir -p /etc/flexlm_exporter
sudo vi /etc/flexlm_exporter/licenses.yml
```

```yaml
---
licenses:
  - name: actel
    license_server: 1702@sirocco
    monitor_users: true
    monitor_reservations: true

  - name: cam350
    license_server: 7102@phi,7102@khi,7102@psi
    monitor_users: true
    monitor_reservations: true

  - name: femap
    license_server: 1745@phi,1745@khi,1745@psi
    monitor_users: true
    monitor_reservations: true

  - name: mathcad_div
    license_server: 27014@sxwtls401n.common.airbusds.corp,27014@sxwtls402n.common.airbusds.corp,27014@sxwtls403n.common.airbusds.corp
    monitor_users: true
    monitor_reservations: true

  - name: matlab
    license_server: 2010@phi,2010@khi,2010@psi
    monitor_users: true
    monitor_reservations: true

  - name: siemens
    license_server: 1717@phi,1717@khi,1717@psi
    monitor_users: true
    monitor_reservations: true

  - name: mentor_corp
    license_server: 1717@covmlic01
    monitor_users: true
    monitor_reservations: true

  - name: mentor_div
    license_server: 1717@covmlic01.common.airbusds.corp
    monitor_users: true
    monitor_reservations: true

  - name: siemens_padspro
    license_server: 1717@sxnidf531w
    monitor_users: true
    monitor_reservations: true

  - name: nanoxplore
    license_server: 28000@phi,28000@khi,28000@psi
    monitor_users: true
    monitor_reservations: true

  - name: orcad
    license_server: 5280@phi,5280@khi,5280@psi
    monitor_users: true
    monitor_reservations: true

  - name: ptc
    license_server: 7788@phi,7788@khi,7788@psi
    monitor_users: true
    monitor_reservations: true

  - name: simetrix
    license_server: 27010@phi,27010@khi,27010@psi
    monitor_users: true
    monitor_reservations: true

  - name: synopsys
    license_server: 27000@phi,27000@khi,27000@psi
    monitor_users: true
    monitor_reservations: true

  - name: synopsys_corp
    license_server: 27020@covmlic01
    monitor_users: true
    monitor_reservations: true

  - name: synopsys_div
    license_server: 27020@covmlic01.common.airbusds.corp
    monitor_users: true
    monitor_reservations: true

  - name: timingdesigner
    license_server: 2100@phi,2100@khi,2100@psi
    monitor_users: true
    monitor_reservations: true

  - name: vectorcast
    license_server: 7650@phi,7650@khi,7650@psi
    monitor_users: true
    monitor_reservations: true

  - name: xilinx
    license_server: 2200@phi,2200@khi,2200@psi
    monitor_users: true
    monitor_reservations: true
```

⚠️ Indentation **espaces uniquement**, jamais de tabulation.

```bash
sudo chown -R flexlm_exporter:flexlm_exporter /etc/flexlm_exporter

# Validation syntaxe YAML
python3 -c "import yaml; yaml.safe_load(open('/etc/flexlm_exporter/licenses.yml'))" && echo "YAML valide"
```

---

## Étape 6 — Service systemd

```bash
sudo tee /etc/systemd/system/flexlm_exporter.service > /dev/null <<'EOF'
[Unit]
Description=FlexLM Exporter
After=network.target

[Service]
User=flexlm_exporter
Group=flexlm_exporter
Type=simple
ExecStart=/usr/share/flexlm_exporter/flexlm_exporter \
  --path.lmutil=/usr/share/flexlm_exporter/lmutil \
  --path.config=/etc/flexlm_exporter/licenses.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now flexlm_exporter
sudo systemctl status flexlm_exporter --no-pager
```

---

## Étape 7 — Vérification des métriques

```bash
curl -s http://localhost:9319/metrics | grep flexlm | head -30
```

Avec 19 pools de licences (dont plusieurs triplets), le premier scrape peut
prendre plusieurs secondes.

**En cas d'erreur sur une licence précise :**
```bash
sudo journalctl -u flexlm_exporter -n 50 --no-pager
```

---

## Étape 8 — Firewall

```bash
sudo firewall-cmd --permanent --add-port=9319/tcp
sudo firewall-cmd --reload
```

---

## Étape 9 — Intégration Prometheus

```bash
sudo vi /etc/prometheus/prometheus.yml
```

Ajouter dans `scrape_configs` :
```yaml
  - job_name: 'flexlm'
    scrape_interval: 60s
    scrape_timeout: 45s
    static_configs:
      - targets: ['localhost:9319']
```

⚠️ Intervalle volontairement long (60s vs 15s pour node_exporter) : interroger
19 pools via `lmutil` sur le réseau prend du temps et sollicite les serveurs
de licences — ne pas scraper trop souvent.

```bash
promtool check config /etc/prometheus/prometheus.yml
sudo systemctl reload prometheus
```

Vérifier sur `/targets` que le job `flexlm` apparaît en **UP**.

---

## Étape 10 — Dashboard Grafana

Dashboard prêt à l'emploi dans le dépôt GitHub du projet (dossier `dashboards/`).

**Dashboards → New → Import → Upload JSON file**, puis sélectionner la
datasource Prometheus.

**Métriques principales :**
- `flexlm_feature_issued` — licences disponibles pour une feature
- `flexlm_feature_used` — licences actuellement utilisées
- `flexlm_feature_used_users` — détail par utilisateur connecté
- `flexlm_feature_expiration_seconds` — date d'expiration (timestamp Unix)

**Requête PromQL rapide (taux d'occupation par feature) :**
```promql
flexlm_feature_used / flexlm_feature_issued * 100
```

---

## Tableau récapitulatif de dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `lmutil`: "No such file or directory" alors que le fichier existe | Interpréteur LSB manquant (RHEL 9) | Étape 3 — créer le lien symbolique `ld-lsb-x86-64.so.3` |
| Service `203/EXEC` | Droits d'exécution ou propriétaire incorrects | `chmod 755` + `chown` sur les 2 binaires |
| `/metrics` vide | `lmutil` ne fonctionne pas encore | Refaire le test manuel de l'étape 4 |
| Une licence précise en erreur dans les logs | Format `port@host` incorrect | Tester ce serveur isolément avec `lmutil lmstat -c PORT@HOST -a` |
| YAML refuse de charger | Tabulation au lieu d'espaces | Test Python de l'étape 5 |
| Target Prometheus DOWN | Service pas démarré ou firewall | `curl localhost:9319/metrics` en local d'abord |

---

## Pour les prochaines machines

Répéter les étapes 0 à 4 en particulier (téléchargement, lmutil, **fix LSB**,
test). Les étapes 5 à 10 ne concernent que la machine Prometheus elle-même
(une seule instance), pas chaque machine à monitorer — sauf si un jour
plusieurs machines Prometheus/flexlm_exporter distinctes sont déployées.
