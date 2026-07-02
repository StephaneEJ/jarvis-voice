# Contribuer à Jarvis Voice

Ce projet est né d'un besoin réel : quand on travaille avec une IA comme OpenCode ou Claude Code, on passe son temps à fixer l'écran pour savoir si quelque chose s'est passé. L'idée : laisser l'IA travailler, faire autre chose, et être alerté vocalement quand c'est important.

## Signaler un bug

Ouvre une issue GitHub (ou écris à stephmyej+jarvis@gmail.com) en indiquant :

- Ton OS (Linux / Mac / Windows)
- L'outil concerné (OpenCode ou Claude Code) et sa version
- Ce qui s'est passé vs ce que tu attendais

## Proposer une fonctionnalité

Les idées sont bienvenues. Quelques axes déjà identifiés :

- Support Windows natif plus robuste (le lecteur audio est encore fragile)
- Meilleure détection des erreurs (Go, Rust, Java...)
- Mode « résumé de fin de journée »
- Support d'autres langues
- Interface graphique simple pour la configuration

## Contribuer du code

1. Fork le dépôt
2. Crée une branche pour ta modification
3. Teste sur au moins un des trois OS supportés (précise lequel dans la PR)
4. Ouvre une pull request

Points d'attention :

- Chaque fonctionnalité doit exister en version bash (`.sh`) **et** PowerShell (`.ps1`) quand elle touche les hooks ou la commande `jarvis`
- Aucun secret en dur : toute configuration passe par `~/.claude/jarvis.conf`
- Pas de nouvelle dépendance réseau sans fallback local

## Soutenir le projet

Si Jarvis t'est utile : [buymeacoffee.com/stephmyej](https://buymeacoffee.com/stephmyej). Ce n'est pas une obligation — le projet reste gratuit et open-source quoi qu'il arrive.
