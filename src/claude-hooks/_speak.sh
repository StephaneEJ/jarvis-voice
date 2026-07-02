#!/usr/bin/env bash
# _speak.sh — Fonction TTS partagee par les hooks Jarvis (Linux + Mac)
# Usage : source "$(dirname "$0")/_speak.sh" && jarvis_speak "Texte"

export PATH="$HOME/.local/bin:$PATH"

# Piper local (Linux)
PIPER_BIN="$HOME/piper/piper/piper"
PIPER_MODEL="$HOME/piper/models/fr_FR-tom-medium.onnx"

# Lire la config
JARVIS_VOICE=$(grep "^JARVIS_VOICE=" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
JARVIS_VOICE="${JARVIS_VOICE:-fr-FR-HenriNeural}"
JARVIS_RATE=$(grep "^JARVIS_RATE=" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
JARVIS_RATE="${JARVIS_RATE:-+25%}"
JARVIS_REMOTE=$(grep "^JARVIS_REMOTE=" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
JARVIS_TELEGRAM=$(grep "^JARVIS_TELEGRAM=" ~/.claude/jarvis.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')

# Detection OS
_JARVIS_OS="linux"
[[ "$(uname)" == "Darwin" ]] && _JARVIS_OS="mac"

# Jouer un fichier audio selon l'OS
_play_audio() {
    local file="$1"
    if [[ "$_JARVIS_OS" == "mac" ]]; then
        afplay "$file" 2>/dev/null
    else
        paplay "$file" 2>/dev/null || aplay -q "$file" 2>/dev/null
    fi
}

# Envoyer sur Telegram si active
_telegram_send() {
    local file="$1"
    [[ "$JARVIS_TELEGRAM" != "true" ]] && return 0
    local send_script="${HOME}/.local/bin/jarvis-telegram-send"
    if [[ -x "$send_script" && -f "$file" && -s "$file" ]]; then
        "$send_script" --voice "$file" "" &
    fi
}

# Mode remote : deposer le fichier au lieu de jouer localement
_remote_output() {
    local file="$1"
    local remote_dir="/tmp/jarvis-remote-audio"
    if [[ "$JARVIS_REMOTE" == "true" && -d "$remote_dir" ]]; then
        cp "$file" "$remote_dir/" 2>/dev/null
        return 0
    fi
    return 1
}

jarvis_speak() {
    local text="$1"
    [[ -z "$text" ]] && return 0

    local tmpfile
    tmpfile=$(mktemp /tmp/jarvis_XXXXXX.mp3)

    # 1. Edge TTS (internet, voix naturelle)
    if command -v edge-tts &>/dev/null; then
        edge-tts --voice "$JARVIS_VOICE" --rate "$JARVIS_RATE" --text "$text" --write-media "$tmpfile" 2>/dev/null
        if [[ -s "$tmpfile" ]]; then
            _telegram_send "$tmpfile"
            if ! _remote_output "$tmpfile"; then
                _play_audio "$tmpfile"
            fi
            rm -f "$tmpfile"
            return 0
        fi
    fi

    # 2. Fallback Piper (local, sans internet — Linux)
    rm -f "$tmpfile"
    if [[ -x "$PIPER_BIN" && -f "$PIPER_MODEL" ]]; then
        local wavfile
        wavfile=$(mktemp /tmp/jarvis_XXXXXX.wav)
        echo "$text" | "$PIPER_BIN" --model "$PIPER_MODEL" --output_file "$wavfile" 2>/dev/null
        if [[ -s "$wavfile" ]]; then
            _telegram_send "$wavfile"
            if ! _remote_output "$wavfile"; then
                _play_audio "$wavfile"
            fi
            rm -f "$wavfile"
            return 0
        fi
        rm -f "$wavfile"
    fi

    # 3. Fallback natif
    if [[ "$_JARVIS_OS" == "mac" ]]; then
        say -v Thomas "$text" 2>/dev/null
    else
        espeak-ng -v fr -s160 "$text" 2>/dev/null
    fi
}
