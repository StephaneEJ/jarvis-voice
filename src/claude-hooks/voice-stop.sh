#!/usr/bin/env bash
# voice-stop.sh — Hook Stop Claude Code
# Vocalise un résumé de la dernière réponse de Claude.

# Vérifier si Jarvis est activé
JARVIS_ENABLED=$(grep "^JARVIS_ENABLED" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
[[ "$JARVIS_ENABLED" != "true" ]] && exit 0

JARVIS_MODE=$(grep "^JARVIS_MODE" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
JARVIS_MODE="${JARVIS_MODE:-court}"

input=$(cat)

# Éviter la boucle infinie
stop_hook_active=$(echo "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('stop_hook_active', False))
except Exception:
    print('False')
" 2>/dev/null)
[[ "$stop_hook_active" == "True" ]] && exit 0

# Extraire last_assistant_message et générer un résumé
summary=$(echo "$input" | python3 -c "
import json, sys, re

def clean_for_speech(text):
    if not text:
        return ''
    text = re.sub(r'\x60\x60\x60[\s\S]*?\x60\x60\x60', '', text)
    text = re.sub(r'\x60[^\x60]+\x60', '', text)
    text = re.sub(r'#{1,6}\s+', '', text)
    text = re.sub(r'\*\*', '', text)
    text = re.sub(r'\*', '', text)
    text = re.sub(r'\|[^\n]+\|', '', text)
    text = re.sub(r'^[-*]\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'^\d+\.\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'\[\[([^\]]+)\]\]', r'\1', text)
    text = re.sub(r'^>\s+', '', text, flags=re.MULTILINE)
    text = re.sub(r'---+', '', text)
    # Symboles spéciaux lus littéralement par TTS
    text = text.replace('\u2122', '')       # ™
    text = text.replace('\u00AE', '')       # ®
    text = text.replace('\u00A9', '')       # ©
    text = text.replace('\u2026', '...')    # …
    text = text.replace('\u2014', ', ')     # — tiret cadratin
    text = text.replace('\u2013', ', ')     # – tiret demi-cadratin
    text = text.replace('\u00AB', '')       # «
    text = text.replace('\u00BB', '')       # »
    text = re.sub(r'[~^]', '', text)
    # Chemins de fichiers et URLs
    text = re.sub(r'[A-Za-z]:\\[\w\\./\- ]+', '', text)       # chemins Windows
    text = re.sub(r'/[\w./\-]+(?:/[\w./\-]+)+', '', text)     # chemins Unix
    text = re.sub(r'https?://\S+', '', text)                  # URLs
    text = text.replace('\x60', '')         # backticks restants
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()

try:
    d = json.load(sys.stdin)
    text = d.get('last_assistant_message', '')
    if not text:
        sys.exit(0)

    clean = clean_for_speech(text)
    if not clean:
        sys.exit(0)

    flat = re.sub(r'\n+', ' ', clean).strip()
    sentences = re.findall(r'[^.!?]+[.!?]+', flat)

    mode = '$JARVIS_MODE'
    if mode == 'coach':
        print(flat)
    else:
        max_len = 250 if mode == 'court' else 600
        summary = ''
        for s in sentences:
            if len(summary + s) > max_len:
                break
            summary += s.strip() + ' '
        print(summary.strip() or flat[:max_len])
except Exception:
    pass
" 2>/dev/null)

[[ -z "$summary" ]] && exit 0

# Parler
source "$(dirname "$0")/_speak.sh"
jarvis_speak "$summary"

exit 0
