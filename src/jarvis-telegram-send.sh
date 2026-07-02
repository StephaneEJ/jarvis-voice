#!/usr/bin/env bash
# jarvis-telegram-send — Envoie un message texte ou vocal sur Telegram
# Usage :
#   jarvis-telegram-send "Texte du message"
#   jarvis-telegram-send --voice /chemin/fichier.mp3 "Caption optionnelle"

CONF="${HOME}/.claude/jarvis.conf"

get() { grep "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d ' '; }

TOKEN=$(get JARVIS_TELEGRAM_TOKEN)
CHAT_ID=$(get JARVIS_TELEGRAM_CHAT_ID)

[[ -z "$TOKEN" || -z "$CHAT_ID" ]] && {
    echo "Erreur : JARVIS_TELEGRAM_TOKEN ou JARVIS_TELEGRAM_CHAT_ID non configure." >&2
    echo "Lance 'jarvis telegram on' pour configurer." >&2
    exit 1
}

API="https://api.telegram.org/bot${TOKEN}"

# Mode vocal : --voice <fichier> [caption]
if [[ "$1" == "--voice" ]]; then
    VOICE_FILE="$2"
    CAPTION="${3:-}"
    [[ ! -f "$VOICE_FILE" ]] && { echo "Fichier introuvable : $VOICE_FILE" >&2; exit 1; }
    curl -s -X POST "${API}/sendVoice" \
        -F "chat_id=${CHAT_ID}" \
        -F "voice=@${VOICE_FILE}" \
        -F "caption=${CAPTION}" \
        > /dev/null 2>&1
    exit $?
fi

# Mode audio : --audio <fichier> [caption]
if [[ "$1" == "--audio" ]]; then
    AUDIO_FILE="$2"
    CAPTION="${3:-}"
    [[ ! -f "$AUDIO_FILE" ]] && { echo "Fichier introuvable : $AUDIO_FILE" >&2; exit 1; }
    curl -s -X POST "${API}/sendAudio" \
        -F "chat_id=${CHAT_ID}" \
        -F "audio=@${AUDIO_FILE}" \
        -F "caption=${CAPTION}" \
        > /dev/null 2>&1
    exit $?
fi

# Mode texte : message simple
TEXT="$*"
[[ -z "$TEXT" ]] && { echo "Usage : jarvis-telegram-send \"message\"" >&2; exit 1; }

curl -s -X POST "${API}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${TEXT}" \
    > /dev/null 2>&1
exit $?
