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

## 12/11/2026 — C3 : tests et essai sur une session de test, sans voix (nuit autonome, conducteur C)

- Essai réel : espace cmux dédié « TEST JARVIS-VOICE C3 » (Claude Code Haiku, mode `default`), superviseur K du clone d'exécution sur une racine isolée du scratchpad, `jarvis alertes tick --texte` toutes les 10 à 15 s ; aucune voix, aucun fichier du Cockpit ni installé touché.
- Deux boîtes d'autorisation réelles : deux annonces, une par arrêt, puis silence ; accord et refus par Échap donnent `terminee` chez K, sans annonce.
- Écarts trouvés : `/clear` d'une autre session vu comme `processus_absent` (corrigé : surface occupée par une autre session ouverte) ; commande longue vue `autorisation_probable` par K (limite documentée).
- Trois tests de séquences réelles ajoutés (30 au total).
