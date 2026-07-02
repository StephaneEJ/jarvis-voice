#!/usr/bin/env bash
# voice-post-tool.sh — Hook PostToolUseFailure Claude Code
# Annonce vocalement les erreurs d'outils.

# Vérifier si Jarvis est activé
JARVIS_ENABLED=$(grep "^JARVIS_ENABLED" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
[[ "$JARVIS_ENABLED" != "true" ]] && exit 0

input=$(cat)

# Extraire le nom de l'outil et un résumé de l'erreur
msg=$(echo "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', 'outil inconnu')
    error = d.get('error', '')
    lines = [l.strip() for l in error.strip().splitlines() if l.strip()]
    detail = lines[-1] if lines else 'erreur inconnue'
    detail = detail[:80]
    print(f'Attention, erreur sur {tool}. {detail}')
except Exception:
    print('Attention, une erreur a été détectée.')
" 2>/dev/null)

[[ -z "$msg" ]] && msg="Attention, une erreur a été détectée."

# Parler
source "$(dirname "$0")/_speak.sh"
jarvis_speak "$msg"

exit 0
