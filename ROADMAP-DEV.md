# ROADMAP-DEV

## Où j'en suis — 12/11 01:45
Résultat : Q — alertes vocales de blocage et points périodiques, à partir du superviseur K et de la file P du Cockpit
Lot : 2/3 — Annonces bornées, déduplication et silence (C2 de la nuit du 12/11)
Terminé quand : une session pilotée bloquée est annoncée une seule fois par `jarvis-voice`, le reste regroupé en points, rythme validé par Stéphane
Jalons : [x] C1 reprise et roadmap [x] C2 annonces bornées, déduplication, silence [ ] C3 tests et essai sur session de test [ ] essai vocal réel et réglage du rythme avec Stéphane
Dernier acquis : commit 7334833 — `jarvis alertes` (bash et PowerShell) et `jarvis_alertes.py`, 27 tests unitaires verts ; lecture réelle du registre K sans écriture
Prochaine action : C3 — bloquer une session de test, observer le registre K, vérifier `jarvis alertes tick --texte` (une seule annonce), sans voix la nuit
Bloqué : rien ; format de la file P provisoire tant que P n'est pas livré (A7) ; écart installé / dépôt (voir Risques ouverts)

## Objectif final

**Résultat utilisateur :** Stéphane entend, sans regarder l'écran, ce qui mérite son attention dans les sessions Claude Code, OpenCode et Codex : la fin de réponse, une erreur, une autorisation attendue, et désormais un blocage ou une décision en attente remontés par le Cockpit Jarvis. Une annonce n'est jamais répétée, le reste est regroupé en points périodiques ou à la demande. Stéphane fixe le rythme.

**Hors périmètre de ce dépôt :** le registre des sessions (superviseur K) et la file des décisions (P) vivent dans le dépôt `JARVIS COCKPIT`. `jarvis-voice` les lit par une interface bornée, sans copie de code entre les dépôts.

## Résultats

| Résultat | Statut | Terminé quand | Preuves attendues |
|---|---|---|---|
| V2.1 — feedback vocal OpenCode et Claude Code | livré (commit `fb8ada6`) | Résumé de fin de réponse, alerte d'erreur, « j'ai besoin de toi », Telegram, mode remote, sur Linux, Mac et Windows | Installateurs, hooks bash et PowerShell |
| Q — alertes de blocage et points périodiques | en_cours | Une session pilotée bloquée (autorisation probable, erreur, interruption) ou une décision en attente est annoncée une seule fois, selon des règles de silence propres à `jarvis-voice` ; le reste est regroupé en points périodiques ou à la demande | Tests de déduplication et de silence ; annonce réelle d'un blocage d'une session de test ; rythme validé par Stéphane |
| R — réconciliation installé / dépôt | à_faire | La version installée sur le Mac et le dépôt ne divergent plus, et l'installateur ne régresse pas les ajouts locaux | Diff vide entre `src/` et les fichiers installés, après accord de Stéphane |

## Lot courant

**Résultat :** Q, nuit autonome du 12/11/2026, conducteur C.
**Statut :** en_cours
**Mode d'exécution :** autonome, contrat de nuit du Cockpit (`JARVIS COCKPIT/ROADMAP-DEV.md`, section Lot courant)

### Contrat (repris du Cockpit)

- **C1** reprise du dépôt dormant selon son `AGENTS.md` : ce fichier, `ROADMAP-JOURNAL.md`, `scripts/check.sh`.
- **C2** annonces de blocage et de décisions en attente, lues dans le registre du superviseur K et la file P par une interface bornée, avec déduplication et règles de silence.
- **C3** tests et essai sur une session de test, sans voix réelle la nuit.

**Livrée :** branche `nuit/<étape>`, contrôles verts, PR fusionnée dans `main`, et `docs/preuves/nuit-2026-11-12/<étape>.md` qui commence par `Statut : livré`.

**Contrôles :** `bash scripts/check.sh` (`bash -n` sur chaque `.sh`, `node --check` sur chaque `.js`, `pytest` si `tests/` existe, `git diff --check`). Critère de nuit : `scripts/nuit/verifier_etape.py <étape>` du clone d'exécution du Cockpit.

**Interdits :** suppression irréversible, suppression de branche, force-push, réécriture d'historique, appel payant, secret affiché ou commité, écriture hors de ce worktree (les fichiers installés dans `~/.claude/hooks/` et `~/.local/bin/` ne sont pas touchés la nuit).

## Risques ouverts

- **Version installée divergente du dépôt (constaté le 12/11, lecture seule).** `~/.local/bin/jarvis` diffère de `src/jarvis.sh` (sous-commandes `lang`, `en`, `claude` et voix anglaises présentes seulement à l'installé ; `notify`, `remote`, `telegram` présentes seulement au dépôt). `_speak.sh` installé ajoute un séquenceur audio par verrou (`/tmp/jarvis_audio_lock`) et le chemin Python 3.9 ; `voice-stop.sh` installé saute l'exécution sous cron (`JARVIS_CRON=1`). `jarvis.js` est identique. `jarvis-telegram-send` n'est pas installé. Conséquence : relancer `install.sh` écraserait ces ajouts locaux. Décision de Stéphane requise avant toute réconciliation (Résultat R).
- **Tests sans pytest.** `pytest` n'est pas installé sur le Mac : les tests vivent dans `tests-unitaires/` (bibliothèque standard, lancés par `scripts/check.sh`), pas dans `tests/`, qui ferait échouer le critère de nuit. Le critère de nuit ne les lance donc pas : seul `check.sh` les rejoue.
- **Format de la file P provisoire.** `orchestrateur/decisions.json` est une hypothèse de `jarvis-voice` (voir `docs/ALERTES-COCKPIT.md`) ; à aligner sur le contrat de P quand il sera livré dans le Cockpit.
- **Rythme d'appel non installé.** Aucun cron ni boucle n'appelle `jarvis alertes tick` : le rythme et les heures de silence (défaut 22-07) sont à valider avec Stéphane.
- **Parité bash / PowerShell** (règle de `CONTRIBUTING.md`) : toute nouveauté des hooks ou de `jarvis` doit exister en `.sh` et `.ps1`, ce qui double le coût de Q.

## Décisions

- 12/11/2026 — Q : cœur en Python (bibliothèque standard, déjà requis par l'installateur), sous-commande `jarvis alertes` en bash et en PowerShell qui n'en font que l'appel et la voix ; interface avec le Cockpit par lecture seule de `orchestrateur/registre.json` (ou d'une sortie `get_state_summary` v0.4) et de `orchestrateur/decisions.json`, sans code partagé.
- 12/11/2026 — Dépôt `jarvis-voice` réactivé pour le résultat Q (autorisation de Stéphane du 12/11, contrat de nuit du Cockpit).
