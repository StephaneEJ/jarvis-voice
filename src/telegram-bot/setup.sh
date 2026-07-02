#!/usr/bin/env bash
# setup.sh — Deploiement du bot Telegram Claude (interaction avec Claude via Telegram)
# Usage : bash setup.sh
# Prerequis : serveur Linux avec Node.js, acces internet, token Anthropic + token Telegram Bot

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  [OK] $1${NC}"; }
warn() { echo -e "${YELLOW}  [!!] $1${NC}"; }
err()  { echo -e "${RED}  [ERR] $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}>>> $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_DIR="$HOME/telegram-bot"
SERVICE_NAME="claude-telegram"

echo ""
echo "  +================================================+"
echo "  |   Deploiement Bot Telegram Claude               |"
echo "  |   Interagir avec Claude depuis Telegram          |"
echo "  +================================================+"
echo ""

# --- Prerequis ---
step "Verification des prerequis"

command -v node &>/dev/null || err "Node.js requis. Installe-le : sudo apt install nodejs"
command -v npm &>/dev/null || err "npm requis. Installe-le : sudo apt install npm"
command -v git &>/dev/null || err "Git requis. Installe-le : sudo apt install git"
ok "Node.js $(node --version), npm $(npm --version), git"

# --- Clone ou mise a jour du repo ---
step "Installation du bot"

# Commit epingle de linuz90/claude-telegram-bot (audite a cette version).
# Pour mettre a jour : verifier le diff upstream puis remplacer ce SHA.
BOT_COMMIT="725552680b1bbf1c9ce195075140271f2af9b07a"

if [[ -d "$BOT_DIR/.git" ]]; then
    echo "  Repo existant detecte, alignement sur le commit epingle..."
    cd "$BOT_DIR"
    git fetch origin 2>/dev/null || warn "Impossible de recuperer les mises a jour"
    git checkout --quiet "$BOT_COMMIT" 2>/dev/null || warn "Commit epingle introuvable (repo modifie localement ?)"
    ok "Repo aligne sur $BOT_COMMIT"
else
    echo "  Clonage de linuz90/claude-telegram-bot..."
    git clone https://github.com/linuz90/claude-telegram-bot.git "$BOT_DIR"
    cd "$BOT_DIR"
    git checkout --quiet "$BOT_COMMIT"
    ok "Repo clone dans $BOT_DIR (commit $BOT_COMMIT)"
fi

cd "$BOT_DIR"

# --- Installation des dependances ---
step "Installation des dependances npm"

npm install --production --silent 2>/dev/null
ok "Dependances installees"

# --- Configuration .env ---
step "Configuration"

if [[ -f "$BOT_DIR/.env" ]]; then
    warn ".env existant conserve (pas ecrase)"
    echo "  Pour reconfigurer : edite $BOT_DIR/.env"
else
    if [[ -f "$SCRIPT_DIR/env.template" ]]; then
        cp "$SCRIPT_DIR/env.template" "$BOT_DIR/.env"
    else
        cat > "$BOT_DIR/.env" << 'ENVEOF'
# Bot Telegram Claude — Configuration
# Remplir les valeurs ci-dessous

# Token du bot Telegram (depuis @BotFather)
TELEGRAM_BOT_TOKEN=

# Cle API Anthropic (depuis console.anthropic.com)
ANTHROPIC_API_KEY=

# Modele Claude a utiliser
CLAUDE_MODEL=claude-sonnet-4-6

# Chat IDs autorises (separes par des virgules, vide = tous)
ALLOWED_CHAT_IDS=

# Langue par defaut
DEFAULT_LANGUAGE=fr
ENVEOF
    fi

    echo ""
    echo "  Le fichier .env a ete cree. Tu dois le remplir :"
    echo "  $BOT_DIR/.env"
    echo ""

    # Demander les tokens interactivement
    read -rp "  Token Telegram Bot (@BotFather) : " tg_token
    read -rp "  Cle API Anthropic :               " api_key
    read -rp "  Ton chat_id Telegram (optionnel) : " chat_id

    if [[ -n "$tg_token" ]]; then
        sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=$tg_token|" "$BOT_DIR/.env"
    fi
    if [[ -n "$api_key" ]]; then
        sed -i "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$api_key|" "$BOT_DIR/.env"
    fi
    if [[ -n "$chat_id" ]]; then
        sed -i "s|^ALLOWED_CHAT_IDS=.*|ALLOWED_CHAT_IDS=$chat_id|" "$BOT_DIR/.env"
    fi

    ok "Configuration sauvegardee"
fi

# --- Service systemd (user) ---
step "Creation du service systemd"

SERVICE_DIR="$HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_DIR/${SERVICE_NAME}.service" << SVCEOF
[Unit]
Description=Bot Telegram Claude (@your_bot_name)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$BOT_DIR
ExecStart=$(command -v node) $BOT_DIR/index.js
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=default.target
SVCEOF

# Recharger et activer
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME" 2>/dev/null
ok "Service cree : $SERVICE_NAME"

# --- Demarrage ---
step "Demarrage du bot"

# Verifier que .env est rempli
tg_check=$(grep "^TELEGRAM_BOT_TOKEN=" "$BOT_DIR/.env" | cut -d= -f2)
api_check=$(grep "^ANTHROPIC_API_KEY=" "$BOT_DIR/.env" | cut -d= -f2)

if [[ -n "$tg_check" && -n "$api_check" ]]; then
    systemctl --user restart "$SERVICE_NAME"
    sleep 2
    if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
        ok "Bot demarre et actif"
    else
        warn "Le bot a demarre mais s'est arrete — verifie les logs :"
        echo "  journalctl --user -u $SERVICE_NAME -n 20"
    fi
else
    warn "Tokens manquants dans .env — le bot ne sera pas demarre"
    echo "  1. Edite $BOT_DIR/.env avec tes tokens"
    echo "  2. Puis lance : systemctl --user start $SERVICE_NAME"
fi

# --- Configuration Jarvis (vocal vers Telegram) ---
step "Liaison avec Jarvis Voice"

JARVIS_CONF="$HOME/.claude/jarvis.conf"
if [[ -f "$JARVIS_CONF" ]]; then
    # Recuperer le token et chat_id pour Jarvis
    if [[ -n "$tg_token" ]]; then
        # Ecrire dans jarvis.conf si pas deja present
        grep -q "^JARVIS_TELEGRAM_TOKEN=" "$JARVIS_CONF" 2>/dev/null || echo "JARVIS_TELEGRAM_TOKEN=$tg_token" >> "$JARVIS_CONF"
    fi
    if [[ -n "$chat_id" ]]; then
        grep -q "^JARVIS_TELEGRAM_CHAT_ID=" "$JARVIS_CONF" 2>/dev/null || echo "JARVIS_TELEGRAM_CHAT_ID=$chat_id" >> "$JARVIS_CONF"
    fi
    ok "Tokens copies dans jarvis.conf"
    echo "  Pour activer l'envoi vocal : jarvis telegram on"
fi

# --- Resume ---
echo ""
echo "  +================================================+"
echo "  |   Deploiement termine !                         |"
echo "  +================================================+"
echo ""
echo "  Bot Telegram Claude :"
echo "    Repo      : $BOT_DIR"
echo "    Service   : systemctl --user status $SERVICE_NAME"
echo "    Logs      : journalctl --user -u $SERVICE_NAME -f"
echo "    Redemarrer: systemctl --user restart $SERVICE_NAME"
echo ""
echo "  Jarvis Voice vers Telegram :"
echo "    Activer   : jarvis telegram on"
echo "    Desactiver: jarvis telegram off"
echo ""
