# Jarvis Voice

**Feedback vocal pour OpenCode et Claude Code.** Au lieu de fixer ton terminal en attendant que l'IA finisse, tu l'entends.

Quand tu utilises un outil d'IA pour coder, tu passes ton temps à surveiller l'écran : l'IA écrit du code, exécute des commandes, parfois plante, parfois attend ta confirmation. Jarvis résout ça en te parlant à voix haute :

- **Fin de réponse** — un résumé vocal de 2-3 phrases de ce que l'IA vient de faire
- **Erreur détectée** — "Attention, une erreur a été détectée", annoncé immédiatement
- **Confirmation requise** — "J'ai besoin de toi" quand l'outil attend ta permission

Tu peux travailler sur autre chose pendant que l'IA exécute une tâche longue, et être alerté vocalement dès que quelque chose se passe.

## Fonctionnalités

- Résumé court, détaillé, ou lecture complète (mode coach)
- 4 voix naturelles françaises (Microsoft Edge TTS), débit réglable
- Fallback hors-ligne automatique : Piper / espeak-ng (Linux), `say` (Mac), System.Speech (Windows)
- File d'attente audio — pas de superposition de voix
- **Mode Telegram** : reçois les résumés vocaux sur ton téléphone (idéal sur VPS)
- **Mode Remote** : stream audio vers navigateur (VPS → mobile)
- **Bot Telegram Claude** (optionnel) : interagis avec Claude depuis Telegram

## Environnements supportés

| OS | OpenCode | Claude Code |
|---|---|---|
| Linux | Plugin JS + commande `jarvis` (bash) | Hooks shell + settings.json |
| Mac | Plugin JS + commande `jarvis` (bash) | Hooks shell + settings.json |
| Windows | Plugin JS + commande `jarvis` (PowerShell) | Hooks PowerShell + settings.json |

## Confidentialité — à lire avant d'activer

Jarvis envoie du texte à des services externes pour fonctionner. Sois-en conscient si tu travailles sur du code confidentiel :

- **Microsoft Edge TTS** : le texte des résumés (qui peut contenir des extraits de tes réponses IA, noms de fichiers, messages d'erreur) est envoyé aux serveurs Microsoft pour la synthèse vocale. Sans internet ou si tu préfères, les fallbacks locaux (Piper, espeak-ng, `say`, System.Speech) fonctionnent 100 % hors-ligne.
- **Telegram** (uniquement si tu actives `jarvis telegram on`) : les fichiers audio transitent par les serveurs Telegram via ton propre bot.
- **Aucune télémétrie** : Jarvis ne collecte rien, n'envoie rien à l'auteur du projet. Ton token Telegram reste dans `~/.claude/jarvis.conf` sur ta machine.

Pour un mode strictement local : désinstalle `edge-tts` ou coupe internet — Jarvis bascule automatiquement sur la voix locale.

## Prérequis

- Python 3
- Connexion internet (pour la voix naturelle Edge TTS)
- [OpenCode](https://opencode.ai) et/ou Claude Code installé
- Pour Telegram : un bot créé via [@BotFather](https://t.me/BotFather) + `curl`
- Pour le bot Claude Telegram : Node.js + clé API Anthropic

## Installation

### Linux / Mac

```bash
bash install.sh
```

Puis redémarre OpenCode / Claude Code.

### Windows

Clic droit sur `install.ps1` → « Exécuter avec PowerShell », ou :

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

Puis redémarre OpenCode / Claude Code.

L'installateur détecte automatiquement les outils présents (OpenCode, Claude Code, ou les deux) et configure chacun. L'installation dure environ 30 secondes ; à la fin, tu entendras un message vocal de confirmation.

### Bot Telegram Claude (optionnel, Linux)

```bash
cd src/telegram-bot
bash setup.sh
```

Le script clone [linuz90/claude-telegram-bot](https://github.com/linuz90/claude-telegram-bot) (épinglé sur un commit audité), installe les dépendances, configure le `.env` et crée un service systemd utilisateur.

## Utilisation

Jarvis se lance automatiquement. Pour le contrôler depuis le terminal :

```
jarvis status          Voir la configuration actuelle
jarvis on / off        Activer / désactiver le feedback vocal
jarvis shut            Couper la lecture en cours
jarvis voix henri      Changer la voix (joue un test audio)
jarvis mode court      Résumé court — 2-3 phrases (recommandé)
jarvis mode detail     Résumé détaillé
jarvis mode coach      Lit les réponses complètes + transcript
jarvis rate +40%       Changer le débit de parole
jarvis transcript on   Activer le log de conversation
jarvis telegram on     Envoyer les vocaux sur Telegram
jarvis remote on|off   Stream audio vers navigateur (VPS)
jarvis aide            Liste de toutes les commandes
```

## Mode Telegram

1. Crée un bot via @BotFather sur Telegram
2. Récupère le token du bot
3. Envoie un message à ton bot, puis récupère ton chat_id via `https://api.telegram.org/bot<TOKEN>/getUpdates`
4. Lance `jarvis telegram on` — le token et le chat_id te seront demandés

L'envoi utilise l'API Bot Telegram via `curl` — zéro dépendance externe. L'audio est envoyé en message vocal.

## Voix disponibles

| Raccourci | Voix | Notes |
|---|---|---|
| `henri` | fr-FR-HenriNeural | Masculine |
| `remy` | fr-FR-RemyMultilingualNeural | Masculine (défaut Linux/Mac) |
| `denise` | fr-FR-DeniseNeural | Féminine (défaut Windows) |
| `eloise` | fr-FR-EloiseNeural | Féminine alternative |

## Configuration manuelle

Fichier : `~/.claude/jarvis.conf` (Linux/Mac) ou `C:\Users\<toi>\.claude\jarvis.conf` (Windows).

```ini
JARVIS_ENABLED=true              Activer (true) ou désactiver (false)
JARVIS_MODE=court                court, detail, coach
JARVIS_VOICE=fr-FR-HenriNeural   Voix à utiliser
JARVIS_RATE=+25%                 Débit (+0%, +25%, +40%, ...)
JARVIS_TRANSCRIPT=false          Log de conversation
JARVIS_REMOTE=false              Stream audio navigateur
JARVIS_TELEGRAM=false            Envoi vocal Telegram
JARVIS_TELEGRAM_TOKEN=           Token du bot Telegram
JARVIS_TELEGRAM_CHAT_ID=         Chat ID Telegram
```

Les changements sont pris en compte immédiatement, sans redémarrage.

## En cas de problème

- **Jarvis ne parle pas** → redémarre OpenCode / Claude Code, puis `jarvis status` (`JARVIS_ENABLED` doit être `true`)
- **Voix robotique** → connexion internet coupée : Edge TTS est indisponible, la voix de secours locale prend le relais
- **`edge-tts not found`** → `pip3 install edge-tts` (Linux/Mac) ou `python -m pip install edge-tts` (Windows)
- **Commande `jarvis` inconnue** → relance ton terminal après l'installation
- **Claude Code muet sur erreurs/permissions** → vérifie que `~/.claude/settings.json` contient les hooks Jarvis, ou relance l'installateur (merge idempotent)
- **Telegram « Erreur d'envoi »** → vérifie token et chat_id (`jarvis status`), teste `jarvis-telegram-send "test"`, vérifie `curl`

## Structure du projet

```
install.sh / install.ps1        Installateurs Linux+Mac / Windows
src/
  jarvis.js                     Plugin OpenCode (cross-platform)
  jarvis.sh / jarvis.ps1        Commande jarvis (bash / PowerShell)
  jarvis.conf                   Configuration par défaut
  jarvis-telegram-send.{sh,ps1} Envoi messages/vocaux Telegram
  claude-hooks/                 Hooks Claude Code (TTS, erreurs, permissions, résumés)
  telegram-bot/                 Déploiement bot Telegram Claude (Linux)
```

## Contribuer

Bugs, idées, contributions : voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Soutenir

Si Jarvis te fait gagner du temps au quotidien : [buymeacoffee.com/stephmyej](https://buymeacoffee.com/stephmyej). Le projet reste gratuit et open-source quoi qu'il arrive.

## Licence

[MIT](LICENSE)
