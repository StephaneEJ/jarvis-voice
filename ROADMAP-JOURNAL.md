# ROADMAP-JOURNAL

Historique des lots, en ajout seul.

## 12/11/2026 — C1 : reprise du dépôt dormant (nuit autonome, conducteur C)

- Dépôt dormant depuis septembre 2026 (dernier commit fonctionnel `fb8ada6`, Jarvis Voice v2.1).
- Commit local `8c5de98` (renvoi « projet dormant ») publié avec la branche `nuit/C1`, comme autorisé le 12/11 à 01:28.
- Création de `ROADMAP-DEV.md` (bloc « Où j'en suis », résultat Q), de ce journal et de `scripts/check.sh`.
- `AGENTS.md` : le projet n'est plus dormant ; renvoi vers le système de développement et la roadmap.
- Constat en lecture seule : la version installée diverge du dépôt (voir Risques ouverts de la roadmap).

## 12/11/2026 — C2 : annonces bornées, déduplication et silence (nuit autonome, conducteur C)

- `src/claude-hooks/jarvis_alertes.py` : lecture bornée du registre K et de la file P (provisoire), déduplication par arrêt, heures de silence, anti-rafale, points périodiques et à la demande.
- `jarvis alertes [point|tick|etat]` en bash et en PowerShell ; installateurs mis à jour (non relancés sur le Mac).
- `tests-unitaires/` : 27 tests, lancés par `scripts/check.sh` ; interface et règles décrites dans `docs/ALERTES-COCKPIT.md`.
