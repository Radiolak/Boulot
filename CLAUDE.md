# Règles du dépôt

Dépôt de la supervision Grafana/Prometheus des serveurs de calcul CAO. Langue : français.

- Un seul fichier par élément, **toujours la dernière version**. Jamais de numéro de version dans un nom de fichier (`-v22`, `-final`…) : on écrase le fichier et Git garde l'historique.
- Noms de fichiers : minuscules, tirets ou underscores, sans espaces ni accents, avec la bonne extension.
- Où ranger :
  - `dashboards/` : JSON Grafana complets, nommés `NN-sujet.json` (voir le tableau du README). Ne jamais changer l'`uid` d'un dashboard existant.
  - `documentation/` : documentations Word (utilisateurs, managers, glossaire).
  - `installation/` : procédures (`NN-installation-xxx`), `scripts/` (.sh), `binaires/`.
  - `prometheus/` : règles et extraits de configuration Prometheus.
  - `notes/`, `archives/` (fichiers remplacés), `divers/` (hors projet).
- Ne jamais ajouter de recording rules supplémentaires sans accord explicite (pas de charge en plus sur la machine Prometheus).
- Ne jamais committer de mot de passe, token ou clé.
- Après chaque ajout ou renommage, mettre à jour les tableaux du `README.md`.
- Messages de commit en français, courts : `Dashboards : global v22 (info-bulles)`.
