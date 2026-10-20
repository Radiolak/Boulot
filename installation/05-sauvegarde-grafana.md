# Sauvegarde de Grafana

À faire sur **saxfrc0155** (serveur Grafana).

## Ce qui est sauvegardé

| Élément | Emplacement | Contenu |
|---|---|---|
| Base de données | `/var/lib/grafana/grafana.db` | Dashboards, dossiers, sources de données, utilisateurs, droits, préférences |
| Configuration | `/etc/grafana` | `grafana.ini`, provisioning |

La base est copiée **à chaud** avec la commande `.backup` de SQLite : Grafana n'est pas arrêté et la copie reste cohérente. Chaque copie est vérifiée (`PRAGMA integrity_check`).

Résultat dans `/var/backups/grafana/` (accès root uniquement, `grafana.ini` contient des secrets) :

```
grafana_20261020_0230.db.gz         base de données
grafana-conf_20261020_0230.tar.gz   configuration
```

Les sauvegardes de plus de 14 jours sont supprimées automatiquement (`KEEP_DAYS` dans le script).

## Installation (une seule fois)

```bash
# 1. sqlite3 doit être présent
which sqlite3 || sudo dnf install -y sqlite

# 2. Installer le script (copié dans le home au préalable)
sudo install -o root -g root -m 750 ~/backup_grafana.sh /usr/local/sbin/backup_grafana.sh
sudo restorecon -v /usr/local/sbin/backup_grafana.sh      # contexte SELinux

# 3. Premier lancement à la main
sudo /usr/local/sbin/backup_grafana.sh
sudo ls -lh /var/backups/grafana

# 4. Lancement automatique tous les jours à 2 h 30
echo '30 2 * * * root /usr/local/sbin/backup_grafana.sh >/dev/null 2>&1' | sudo tee /etc/cron.d/backup_grafana
sudo chmod 644 /etc/cron.d/backup_grafana
```

## Vérifier

```bash
# Résultat des dernières sauvegardes (OK ou ERREUR)
sudo journalctl -t backup_grafana --since "7 days ago"

# Contrôler qu'une sauvegarde contient bien les dashboards
sudo sh -c 'gunzip -c /var/backups/grafana/grafana_AAAAMMJJ_HHMM.db.gz > /tmp/test_grafana.db'
sudo sqlite3 /tmp/test_grafana.db "select title from dashboard;"
sudo rm -f /tmp/test_grafana.db
```

## Copie hors du serveur (recommandé)

Une sauvegarde qui reste sur le même disque est perdue si le serveur est perdu.
Renseigner `COPY_TO` dans le script avec un dossier sur un partage réseau, par exemple :

```bash
COPY_TO="/chemin/du/partage/backups_grafana"
```

Le dossier doit être accessible en écriture par root. Sur un partage NFS avec l'option `root_squash`, root ne peut pas écrire : choisir un autre emplacement ou demander les droits à l'équipe stockage.

## Restaurer

```bash
sudo systemctl stop grafana-server

# Garder la base actuelle au cas où
sudo cp /var/lib/grafana/grafana.db /var/lib/grafana/grafana.db.avant_restauration

# Remettre la sauvegarde choisie
sudo sh -c 'gunzip -c /var/backups/grafana/grafana_AAAAMMJJ_HHMM.db.gz > /var/lib/grafana/grafana.db'
sudo chown grafana:grafana /var/lib/grafana/grafana.db
sudo chmod 640 /var/lib/grafana/grafana.db
sudo restorecon -v /var/lib/grafana/grafana.db

sudo systemctl start grafana-server
sudo systemctl status grafana-server --no-pager
```

Configuration (si besoin) : `sudo tar -xzf /var/backups/grafana/grafana-conf_AAAAMMJJ_HHMM.tar.gz -C /` puis redémarrer Grafana.

Restaurer une sauvegarde **remplace tout** : les dashboards modifiés après la date de la sauvegarde sont perdus. Pour récupérer un seul dashboard, l'importer plutôt depuis `dashboards/` de ce dépôt.
