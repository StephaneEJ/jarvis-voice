#!/usr/bin/env bash
# jarvis — Commande de controle Jarvis (Linux + Mac)
# Usage : jarvis <commande> [argument]

CONF="${HOME}/.claude/jarvis.conf"

# Detecte l'OS
OS="linux"
[[ "$(uname)" == "Darwin" ]] && OS="mac"

get()     { grep "^$1=" "$CONF" 2>/dev/null | cut -d= -f2 | tr -d ' '; }
set_val() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$CONF" 2>/dev/null; then
        sed -i'' -e "s|^${key}=.*|${key}=${val}|" "$CONF"
    else
        echo "${key}=${val}" >> "$CONF"
    fi
}

resolve_voice() {
    local lower; lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        henri)         echo "fr-FR-HenriNeural" ;;
        denise)        echo "fr-FR-DeniseNeural" ;;
        remy|rémy)     echo "fr-FR-RemyMultilingualNeural" ;;
        eloise|éloïse) echo "fr-FR-EloiseNeural" ;;
        *)             echo "$1" ;;
    esac
}

play_test() {
    local voice="$1" rate="$2"
    local msg="Bonjour, je suis maintenant votre voix."
    local tmp; tmp=$(mktemp /tmp/jarvis_XXXXXX.mp3)
    local args=(--voice "$voice" --text "$msg" --write-media "$tmp")
    [[ -n "$rate" ]] && args+=(--rate "$rate")
    edge-tts "${args[@]}" 2>/dev/null && {
        if [[ "$OS" == "mac" ]]; then
            afplay "$tmp" 2>/dev/null
        else
            paplay "$tmp" 2>/dev/null || aplay -q "$tmp" 2>/dev/null
        fi
        rm -f "$tmp"
    } || echo "  (test vocal echoue — verifie ta connexion internet)"
}

cmd=$(echo "$1" | tr '[:upper:]' '[:lower:]')
arg=$(echo "$2" | tr '[:upper:]' '[:lower:]')

case "$cmd" in
    on)
        set_val JARVIS_ENABLED true
        echo "Jarvis active."
        ;;
    off)
        set_val JARVIS_ENABLED false
        echo "Jarvis desactive."
        ;;
    voix|voice)
        [[ -z "$arg" ]] && { echo "Usage : jarvis voix <henri|denise|remy|eloise>"; exit 1; }
        voice=$(resolve_voice "$arg")
        set_val JARVIS_VOICE "$voice"
        echo "Voix changee : $voice"
        echo "Test en cours..."
        local_rate=$(get JARVIS_RATE)
        local_rate="${local_rate:-+25%}"
        play_test "$voice" "$local_rate"
        ;;
    mode)
        [[ -z "$arg" ]] && { echo "Usage : jarvis mode <court|detail|coach>"; exit 1; }
        case "$arg" in
            court|detail|coach) set_val JARVIS_MODE "$arg"; echo "Mode change : $arg" ;;
            *) echo "Mode inconnu. Choix possibles : court, detail, coach" ; exit 1 ;;
        esac
        if [[ "$arg" == "coach" ]]; then
            set_val JARVIS_TRANSCRIPT true
            echo "Transcript active (mode coach)."
            > /tmp/jarvis-coach-transcript.jsonl
            echo "Fichier transcript reinitialise."
        fi
        ;;
    coach)
        set_val JARVIS_ENABLED true
        set_val JARVIS_MODE coach
        set_val JARVIS_TRANSCRIPT true
        > /tmp/jarvis-coach-transcript.jsonl
        echo ""
        echo "  Mode Coach IA active"
        echo "  --------------------"
        echo "  Jarvis lit les reponses completes."
        echo "  Transcript active."
        echo ""
        echo "  Pour revenir en mode normal : jarvis mode court"
        echo ""
        ;;
    shut|stop|tais-toi|silence)
        touch /tmp/jarvis-stop
        pkill -f "paplay.*/tmp/jarvis_" 2>/dev/null
        pkill -f "edge-tts.*jarvis" 2>/dev/null
        if [[ "$OS" == "mac" ]]; then
            pkill -f "afplay.*/tmp/jarvis_" 2>/dev/null
        fi
        rm -f /tmp/jarvis_*.mp3 /tmp/jarvis_*.wav 2>/dev/null
        echo "Jarvis coupe."
        ;;
    rate|vitesse|debit)
        [[ -z "$arg" ]] && { echo "Usage : jarvis rate <+10%|+25%|+40%|+50%>"; exit 1; }
        if [[ ! "$arg" =~ ^[+-][0-9]+%$ ]]; then
            echo "Format invalide. Exemples : +25%, +40%, -10%"
            exit 1
        fi
        set_val JARVIS_RATE "$arg"
        echo "Debit change : $arg"
        echo "Test en cours..."
        local_voice=$(get JARVIS_VOICE)
        local_voice="${local_voice:-fr-FR-HenriNeural}"
        play_test "$local_voice" "$arg"
        ;;
    transcript)
        case "$arg" in
            on)
                set_val JARVIS_TRANSCRIPT true
                echo "Transcript active."
                ;;
            off)
                set_val JARVIS_TRANSCRIPT false
                echo "Transcript desactive."
                ;;
            show)
                local_file="/tmp/jarvis-coach-transcript.jsonl"
                if [[ -f "$local_file" ]] && [[ -s "$local_file" ]]; then
                    echo ""
                    echo "  Transcript courant :"
                    echo "  --------------------"
                    while IFS= read -r line; do
                        ts=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['timestamp'][:19].replace('T',' '))" 2>/dev/null)
                        role=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['role'])" 2>/dev/null)
                        text=$(echo "$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['text'][:100])" 2>/dev/null)
                        printf "  [%s] %s: %s...\n" "$ts" "$role" "$text"
                    done < "$local_file"
                    echo ""
                else
                    echo "Pas de transcript en cours."
                fi
                ;;
            clear)
                > /tmp/jarvis-coach-transcript.jsonl
                echo "Transcript efface."
                ;;
            *)
                echo "Usage : jarvis transcript <on|off|show|clear>"
                exit 1
                ;;
        esac
        ;;
    remote)
        case "$arg" in
            on)  set_val JARVIS_REMOTE true;  echo "Mode remote active — son sur iPhone uniquement" ;;
            off) set_val JARVIS_REMOTE false; echo "Mode remote desactive — son local" ;;
            *)   echo "Usage : jarvis remote on|off" ;;
        esac
        ;;
    telegram)
        case "$arg" in
            on)
                # Verifier que le token et chat_id sont configures
                local_token=$(get JARVIS_TELEGRAM_TOKEN)
                local_chatid=$(get JARVIS_TELEGRAM_CHAT_ID)
                if [[ -z "$local_token" || -z "$local_chatid" ]]; then
                    echo ""
                    echo "  Configuration Telegram requise."
                    echo ""
                    echo "  1. Cree un bot via @BotFather sur Telegram"
                    echo "  2. Recupere le token du bot"
                    echo "  3. Envoie un message au bot puis recupere ton chat_id"
                    echo "     (via https://api.telegram.org/bot<TOKEN>/getUpdates)"
                    echo ""
                    read -rp "  Token du bot : " local_token
                    read -rp "  Chat ID :      " local_chatid
                    [[ -z "$local_token" || -z "$local_chatid" ]] && { echo "Annule."; exit 1; }
                    set_val JARVIS_TELEGRAM_TOKEN "$local_token"
                    set_val JARVIS_TELEGRAM_CHAT_ID "$local_chatid"
                fi
                set_val JARVIS_TELEGRAM true
                echo "Mode Telegram active — reponses vocales envoyees sur Telegram"
                # Test d'envoi
                SEND_SCRIPT="${HOME}/.local/bin/jarvis-telegram-send"
                if [[ -x "$SEND_SCRIPT" ]]; then
                    "$SEND_SCRIPT" "Mode Telegram active." 2>/dev/null && echo "Test envoye sur Telegram." || echo "Erreur d'envoi."
                else
                    echo "  (script jarvis-telegram-send non trouve — relance l'installateur)"
                fi
                ;;
            off)
                set_val JARVIS_TELEGRAM false
                echo "Mode Telegram desactive."
                ;;
            *)   echo "Usage : jarvis telegram on|off" ;;
        esac
        ;;
    notify)
        case "$arg" in
            on)  set_val JARVIS_NOTIFY true;  echo "Notification active — Jarvis dit 'j'ai besoin de toi' quand l'IA demande une permission" ;;
            off) set_val JARVIS_NOTIFY false; echo "Notification desactivee — plus de 'j'ai besoin de toi'" ;;
            *)   echo "Usage : jarvis notify on|off" ;;
        esac
        ;;
    status)
        echo ""
        echo "  Jarvis — configuration actuelle"
        echo "  --------------------------------"
        printf "  %-14s %s\n" "Active :"     "$(get JARVIS_ENABLED)"
        printf "  %-14s %s\n" "Mode :"       "$(get JARVIS_MODE)"
        printf "  %-14s %s\n" "Voix :"       "$(get JARVIS_VOICE)"
        printf "  %-14s %s\n" "Debit :"      "$(get JARVIS_RATE)"
        notify_val=$(get JARVIS_NOTIFY); printf "  %-14s %s\n" "Notify :" "${notify_val:-true (defaut)}"
        printf "  %-14s %s\n" "Remote :"     "$(get JARVIS_REMOTE)"
        printf "  %-14s %s\n" "Telegram :"   "$(get JARVIS_TELEGRAM)"
        printf "  %-14s %s\n" "Transcript :" "$(get JARVIS_TRANSCRIPT)"
        if [[ -f /tmp/jarvis-coach-transcript.jsonl ]] && [[ -s /tmp/jarvis-coach-transcript.jsonl ]]; then
            local_lines=$(wc -l < /tmp/jarvis-coach-transcript.jsonl)
            printf "  %-14s %s echanges\n" "Log :" "$local_lines"
        fi
        echo ""
        ;;
    aide|help|"")
        echo ""
        echo "  Usage : jarvis <commande> [argument]"
        echo ""
        echo "  jarvis on              Activer le feedback vocal"
        echo "  jarvis off             Desactiver le feedback vocal"
        echo "  jarvis shut            Couper la lecture en cours"
        echo "  jarvis voix <nom>      Changer la voix (teste immediatement)"
        echo "    Voix disponibles : henri, denise, remy, eloise"
        echo "  jarvis mode court      Resume court (2-3 phrases)"
        echo "  jarvis mode detail     Resume detaille"
        echo "  jarvis mode coach      Lit les reponses completes + transcript"
        echo "  jarvis coach           Raccourci : active tout le mode coach"
        echo "  jarvis rate <+XX%>     Changer le debit (ex: +25%, +40%)"
        echo "  jarvis transcript on   Activer le log de conversation"
        echo "  jarvis transcript off  Desactiver le log de conversation"
        echo "  jarvis transcript show Afficher le transcript courant"
        echo "  jarvis transcript clear Effacer le transcript"
        echo "  jarvis notify on|off   Activer/couper le 'j'ai besoin de toi' (permissions)"
        echo "  jarvis remote on|off   Son sur iPhone uniquement (via stream)"
        echo "  jarvis telegram on|off Reponses vocales envoyees sur Telegram"
        echo "  jarvis status          Voir la configuration actuelle"
        echo ""
        ;;
    *)
        echo "Commande inconnue : $1"
        echo "Tape 'jarvis aide' pour voir les commandes disponibles."
        exit 1
        ;;
esac
