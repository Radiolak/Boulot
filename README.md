# Supervision des serveurs de calcul CAO

Supervision Grafana + Prometheus des serveurs de calcul CAO (RHEL) et des licences FlexLM.

Chaque fichier de ce dépôt est **toujours dans sa dernière version**. Les versions précédentes sont dans l'historique Git (bouton *History* sur GitHub).

## Organisation

```
dashboards/        Dashboards Grafana (JSON à importer)
documentation/     Documentations utilisateurs, managers et glossaire (Word)
installation/      Procédures d'installation, scripts et binaires
prometheus/        Règles et configuration Prometheus
notes/             Notes de travail et idées d'évolution
archives/          Anciens fichiers remplacés (gardés pour référence)
divers/            Fichiers hors projet supervision
```

## Dashboards

| Fichier | Titre dans Grafana | UID |
|---|---|---|
| `01-cao-global-overview.json` | Serveurs CAO - Vue globale | `global-overview-dash` |
| `02-cao-detail-serveur.json` | Détail serveur | `server-detail-dash` |
| `03-cao-vue-fpga.json` | Vue FPGA - Utilisateur | `fpga-vue-utilisateur` |
| `04-alertes.json` | Supervision - Alertes | `alerts-overview-dash` |
| `05-cao-trends-capacity.json` | Serveurs CAO - Tendances et capacité | `cao-trends-dash` |
| `06-flexlm-vue-globale.json` | Licences FlexLM - Vue globale | `flexlm-supervision-dash` |
| `07-flexlm-detail-vendeur.json` | Licences FlexLM - Détail éditeur | `flexlm-vendor-detail` |
| `08-flexlm-rapport-licences.json` | Licences FlexLM - Rapport d'utilisation | `flexlm-licence-report` |

**Importer ou mettre à jour un dashboard :** Grafana → Dashboards → New → Import → coller le JSON ou charger le fichier → Import. Le dashboard existant est remplacé grâce à son UID.

## Documentation

| Fichier | Public |
|---|---|
| `documentation-utilisateurs.docx` | Salariés : dashboards Global, Détail serveur, Vue FPGA |
| `documentation-managers.docx` | Managers : FlexLM, alertes, Trends & Capacity |
| `glossaire.docx` | Tous : termes techniques du projet |
| `documentation-de-service.docx` | Tous : présentation du service, accès, support, liens Confluence |
| `mail-de-lancement.txt` | Mail d'annonce de l'outil aux utilisateurs |

## Prometheus

| Fichier | Rôle | Emplacement sur le serveur Prometheus |
|---|---|---|
| `alert_rules.yml` | Alertes ServerDown, HighCPUUsage, HighMemoryUsage | déclaré dans `rule_files` de `prometheus.yml` |
| `reboot_plan.yml` | Calcul de la date du prochain redémarrage planifié | déclaré dans `rule_files` de `prometheus.yml` |
| `scrape_process_exporter.yml` | Job de collecte process_exporter (port 9256) | à ajouter dans `scrape_configs` de `prometheus.yml` |

Après modification d'un fichier de règles : `promtool check rules <fichier>` puis `sudo systemctl reload prometheus`.
Si le fichier a été copié depuis le home : `sudo restorecon -v <fichier>` (contexte SELinux).

## Installation

| Fichier | Contenu |
|---|---|
| `01-installation-prometheus.txt` | Installation de Prometheus |
| `02-installation-grafana.txt` | Installation de Grafana |
| `03-installation-node-exporter.txt` | Installation de node_exporter |
| `04-installation-flexlm-exporter.md` | Installation de flexlm_exporter |
| `installation-complete.html` | Procédure d'installation complète |
| `scripts/install_node_exporter.sh` | Installation de node_exporter sur un serveur |
| `scripts/ajout_machine_node_exporter.sh` | Commandes pour ajouter une machine |
| `scripts/install_process_exporter.sh` | process_exporter + résolution des utilisateurs AD |
| `scripts/install_bogomips.sh` | Collecte des BogoMips (textfile collector) |
| `scripts/generate_uid_map.sh` | Correspondance UID → nom d'utilisateur |
| `scripts/migration_grafana.sh` | Migration vers Grafana 12.3.11 |
| `binaires/node_exporter-1.12.1.linux-amd64.tar.gz` | Binaire node_exporter (serveurs sans accès Internet) |
