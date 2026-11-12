# Jarvis Voice — instructions agent

Projet actif depuis le 12/11/2026 (reprise pour le résultat Q : alertes vocales de blocage et points périodiques).

- Système de développement : `../../2ND_CERVEAU/_System/Système de développement — vue d'ensemble.md`.
- Au démarrage : lire le bloc « Où j'en suis » de `ROADMAP-DEV.md` et l'afficher en 3 lignes avant tout geste. Historique : `ROADMAP-JOURNAL.md` (ajout seul).
- Contrôle avant commit : `bash scripts/check.sh`.
- Toute nouveauté des hooks ou de la commande `jarvis` existe en bash (`.sh`) et en PowerShell (`.ps1`) ; aucun secret en dur, la configuration passe par `~/.claude/jarvis.conf` (voir `CONTRIBUTING.md`).
- Ne pas relancer `install.sh` sur le Mac sans accord : la version installée diverge du dépôt (voir Risques ouverts de la roadmap).
