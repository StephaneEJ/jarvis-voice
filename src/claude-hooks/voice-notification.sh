#!/usr/bin/env bash
# voice-notification.sh — Hook Notification Claude Code
# Interpelle l'utilisateur quand Claude Code a besoin d'une confirmation.

# Vérifier si Jarvis est activé
JARVIS_ENABLED=$(grep "^JARVIS_ENABLED" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
[[ "$JARVIS_ENABLED" != "true" ]] && exit 0

# Toggle dédié : JARVIS_NOTIFY=false → silencieux. Absent/true → parle (défaut).
# Pilotable via : jarvis notify on|off
JARVIS_NOTIFY=$(grep "^JARVIS_NOTIFY" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
[[ "$JARVIS_NOTIFY" == "false" ]] && exit 0

# Parler
source "$(dirname "$0")/_speak.sh"
jarvis_speak "j'ai besoin de toi"

exit 0
