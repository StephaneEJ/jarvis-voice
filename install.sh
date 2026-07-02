#!/usr/bin/env bash
# install.sh — Installateur Jarvis pour Linux et Mac
# Supporte OpenCode + Claude Code + Telegram
# Usage : bash install.sh

set -e

# --- Couleurs ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  [OK] $1${NC}"; }
warn() { echo -e "${YELLOW}  [!!] $1${NC}"; }
err()  { echo -e "${RED}  [ERR] $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}>>> $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Detection OS ---
OS="linux"
[[ "$(uname)" == "Darwin" ]] && OS="mac"

# Voix par defaut selon OS
DEFAULT_VOICE="fr-FR-RemyMultilingualNeural"

echo ""
echo "  +================================================+"
echo "  |   Installation de Jarvis Voice v2.1             |"
echo "  |   Feedback vocal OpenCode + Claude Code         |"
echo "  |   + Mode Telegram                               |"
echo "  +================================================+"
echo "  Plateforme detectee : $OS"
echo ""

# --- Verifications prealables ---
step "Verification des prerequis"

command -v python3  &>/dev/null || err "Python 3 est requis. Installe-le depuis https://python.org"
ok "Python 3 trouve"

HAS_OPENCODE=false
HAS_CLAUDE_CODE=false
command -v opencode &>/dev/null && HAS_OPENCODE=true
[[ -d "$HOME/.claude" ]] && HAS_CLAUDE_CODE=true

$HAS_OPENCODE && ok "OpenCode detecte" || warn "OpenCode non trouve"
$HAS_CLAUDE_CODE && ok "Claude Code detecte (~/.claude/ existe)" || warn "Claude Code non detecte"

# curl pour Telegram
if command -v curl &>/dev/null; then
    ok "curl trouve (requis pour Telegram)"
else
    warn "curl non trouve — le mode Telegram ne fonctionnera pas"
fi

# --- Installation edge-tts ---
step "Installation de Edge TTS (voix Microsoft)"

if python3 -c "import edge_tts" &>/dev/null; then
    ok "edge-tts deja installe"
else
    pip3 install edge-tts --quiet --break-system-packages 2>/dev/null \
        || pip3 install edge-tts --quiet \
        || err "Impossible d'installer edge-tts. Essaie : pip3 install edge-tts"
    ok "edge-tts installe"
fi

# --- Installation espeak-ng (Linux uniquement) ---
if [[ "$OS" == "linux" ]]; then
    step "Installation de espeak-ng (voix de secours)"
    if command -v espeak-ng &>/dev/null; then
        ok "espeak-ng deja installe"
    else
        sudo apt-get install -y espeak-ng -qq 2>/dev/null \
            || warn "espeak-ng non installe (voix de secours indisponible)"
    fi
fi

[[ "$OS" == "mac" ]] && ok "Voix de secours : 'say' (natif macOS)"

# --- Configuration commune ---
step "Configuration de base"

mkdir -p "$HOME/.claude"

# Copie jarvis.conf (sans ecraser si deja existant)
CONF_DEST="$HOME/.claude/jarvis.conf"
if [[ -f "$CONF_DEST" ]]; then
    warn "jarvis.conf existant conserve (pas ecrase)"
    # Ajouter les nouvelles cles si absentes
    grep -q "^JARVIS_RATE=" "$CONF_DEST" 2>/dev/null || echo "JARVIS_RATE=+25%" >> "$CONF_DEST"
    grep -q "^JARVIS_TRANSCRIPT=" "$CONF_DEST" 2>/dev/null || echo "JARVIS_TRANSCRIPT=false" >> "$CONF_DEST"
    grep -q "^JARVIS_REMOTE=" "$CONF_DEST" 2>/dev/null || echo "JARVIS_REMOTE=false" >> "$CONF_DEST"
    grep -q "^JARVIS_TELEGRAM=" "$CONF_DEST" 2>/dev/null || echo "JARVIS_TELEGRAM=false" >> "$CONF_DEST"
    ok "Nouvelles cles ajoutees si absentes"
else
    cp "$SCRIPT_DIR/src/jarvis.conf" "$CONF_DEST"
    # Voix par defaut selon OS
    sed -i'' -e "s|JARVIS_VOICE=.*|JARVIS_VOICE=$DEFAULT_VOICE|" "$CONF_DEST"
    ok "Config installee dans $CONF_DEST (voix : Remy)"
fi

# --- Installation de la commande jarvis ---
step "Installation de la commande 'jarvis'"

DEST="$HOME/.local/bin"
mkdir -p "$DEST"
cp "$SCRIPT_DIR/src/jarvis.sh" "$DEST/jarvis"
chmod +x "$DEST/jarvis"
ok "Commande jarvis installee dans $DEST/jarvis"

# Installer jarvis-telegram-send
cp "$SCRIPT_DIR/src/jarvis-telegram-send.sh" "$DEST/jarvis-telegram-send"
chmod +x "$DEST/jarvis-telegram-send"
ok "Commande jarvis-telegram-send installee"

# Ajout au PATH si necessaire
SHELL_RC=""
[[ -f "$HOME/.zshrc" ]]  && SHELL_RC="$HOME/.zshrc"
[[ -f "$HOME/.bashrc" ]] && SHELL_RC="$HOME/.bashrc"

if [[ -n "$SHELL_RC" ]]; then
    if ! grep -q 'local/bin' "$SHELL_RC" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        warn "PATH mis a jour dans $SHELL_RC — relance ton terminal ou tape : source $SHELL_RC"
    fi
fi
export PATH="$HOME/.local/bin:$PATH"

# =======================================================
# SECTION OPENCODE
# =======================================================
if $HAS_OPENCODE || true; then
    step "Configuration d'OpenCode"

    OPENCODE_PLUGINS="$HOME/.config/opencode/plugins"
    mkdir -p "$OPENCODE_PLUGINS"

    cp "$SCRIPT_DIR/src/jarvis.js" "$OPENCODE_PLUGINS/jarvis.js"
    ok "Plugin installe dans $OPENCODE_PLUGINS/jarvis.js"
fi

# =======================================================
# SECTION CLAUDE CODE
# =======================================================
if [[ -d "$HOME/.claude" ]]; then
    step "Configuration de Claude Code"

    HOOKS_DIR="$HOME/.claude/hooks"
    mkdir -p "$HOOKS_DIR"

    # Copier les hooks
    for hook in _speak.sh voice-post-tool.sh voice-notification.sh voice-stop.sh; do
        cp "$SCRIPT_DIR/src/claude-hooks/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
    done
    ok "Hooks installes dans $HOOKS_DIR/"

    # Merger settings.json (ajout idempotent des hooks)
    SETTINGS="$HOME/.claude/settings.json"
    python3 -c "
import json, os

settings_path = '$SETTINGS'
hooks_dir = os.path.expanduser('~/.claude/hooks')

# Charger ou creer settings.json
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

# S'assurer que hooks existe
if 'hooks' not in settings:
    settings['hooks'] = {}

hooks_config = {
    'PostToolUseFailure': [
        {
            'type': 'command',
            'command': os.path.join(hooks_dir, 'voice-post-tool.sh')
        }
    ],
    'Notification': [
        {
            'type': 'command',
            'command': os.path.join(hooks_dir, 'voice-notification.sh')
        }
    ],
    'Stop': [
        {
            'type': 'command',
            'command': os.path.join(hooks_dir, 'voice-stop.sh')
        }
    ]
}

def has_jarvis_cmd(entry):
    if not isinstance(entry, dict):
        return False
    cmd = entry.get('command', '')
    if 'voice-' in cmd or '_speak' in cmd:
        return True
    for sub in entry.get('hooks', []):
        if isinstance(sub, dict):
            subcmd = sub.get('command', '')
            if 'voice-' in subcmd or '_speak' in subcmd:
                return True
    return False

for event, new_hooks in hooks_config.items():
    existing = settings['hooks'].get(event, [])
    for new_hook in new_hooks:
        already = False
        for i, h in enumerate(existing):
            if has_jarvis_cmd(h):
                if 'hooks' in h and isinstance(h.get('hooks'), list):
                    h['hooks'] = [new_hook]
                else:
                    existing[i] = new_hook
                already = True
                break
        if not already:
            existing.append(new_hook)
    settings['hooks'][event] = existing

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null && ok "settings.json mis a jour (hooks Jarvis)" \
              || warn "Impossible de mettre a jour settings.json automatiquement"
fi

# --- Test de la voix ---
step "Test de la voix"

VOICE=$(grep "^JARVIS_VOICE=" "$CONF_DEST" 2>/dev/null | cut -d= -f2 | tr -d ' ')
VOICE="${VOICE:-$DEFAULT_VOICE}"
RATE=$(grep "^JARVIS_RATE=" "$CONF_DEST" 2>/dev/null | cut -d= -f2 | tr -d ' ')
RATE="${RATE:-+25%}"

echo "  Connexion a Edge TTS en cours..."
edge-tts --voice "$VOICE" --rate "$RATE" \
    --text "Jarvis est maintenant installe. Bonne session de code." \
    --write-media /tmp/jarvis_install_test.mp3 2>/dev/null && {
    if [[ "$OS" == "mac" ]]; then
        afplay /tmp/jarvis_install_test.mp3 2>/dev/null
    else
        paplay /tmp/jarvis_install_test.mp3 2>/dev/null || aplay -q /tmp/jarvis_install_test.mp3 2>/dev/null
    fi
    rm -f /tmp/jarvis_install_test.mp3
    ok "Test vocal reussi"
} || warn "Test vocal echoue (verifie ta connexion internet)"

# --- Resume ---
echo ""
echo "  +================================================+"
echo "  |   Installation terminee !                       |"
echo "  +================================================+"
echo ""
echo "  Environnements configures :"
$HAS_OPENCODE && echo "    [OK] OpenCode (plugin + commande jarvis)"
[[ -d "$HOME/.claude" ]] && echo "    [OK] Claude Code (hooks + settings.json)"
echo "    [OK] Commande jarvis-telegram-send"
echo ""
echo "  Commandes disponibles :"
echo "    jarvis status          -> voir la configuration"
echo "    jarvis off             -> couper la voix"
echo "    jarvis on              -> reactiver"
echo "    jarvis shut            -> couper la lecture en cours"
echo "    jarvis voix denise     -> changer de voix"
echo "    jarvis rate +40%       -> changer le debit"
echo "    jarvis coach           -> mode coach (lecture integrale)"
echo "    jarvis telegram on     -> envoyer les vocaux sur Telegram"
echo "    jarvis aide            -> liste des commandes"
echo ""
echo "  Bot Telegram Claude (optionnel) :"
echo "    cd telegram-bot && bash setup.sh"
echo ""
