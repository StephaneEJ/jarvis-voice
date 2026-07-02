# voice-stop.ps1 — Hook Stop Claude Code (Windows)
# Vocalise un résumé de la dernière réponse de Claude.

# Vérifier si Jarvis est activé
$confPath = "$env:USERPROFILE\.claude\jarvis.conf"
$enabled = "false"
$mode = "court"
if (Test-Path $confPath) {
    $line = Get-Content $confPath | Where-Object { $_ -match "^JARVIS_ENABLED=" } | Select-Object -First 1
    if ($line) { $enabled = ($line -split "=", 2)[1].Trim() }
    $modeLine = Get-Content $confPath | Where-Object { $_ -match "^JARVIS_MODE=" } | Select-Object -First 1
    if ($modeLine) { $mode = ($modeLine -split "=", 2)[1].Trim() }
}
if ($enabled -ne "true") { exit 0 }

# Forcer UTF-8 pour préserver les accents (é, è, ç, à, etc.)
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Lire stdin JSON
$inputText = [Console]::In.ReadToEnd()

try {
    $data = $inputText | ConvertFrom-Json
} catch {
    exit 0
}

# Éviter la boucle infinie
if ($data.stop_hook_active -eq $true) { exit 0 }

# Extraire last_assistant_message
$text = $data.last_assistant_message
if (-not $text) { exit 0 }

# Nettoyage markdown pour la vocalisation
$clean = $text
$clean = $clean -replace '(?s)```.*?```', ''       # blocs de code
$clean = $clean -replace '`[^`]+`', ''              # inline code
$clean = $clean -replace '#{1,6}\s+', ''            # titres
$clean = $clean -replace '\*\*', ''                 # bold
$clean = $clean -replace '\*', ''                   # italic
$clean = $clean -replace '\|[^\n]+\|', ''           # tableaux
$clean = $clean -replace '(?m)^[-*]\s+', ''         # listes
$clean = $clean -replace '(?m)^\d+\.\s+', ''        # listes numérotées
$clean = $clean -replace '\[([^\]]+)\]\([^)]+\)', '$1'  # liens
$clean = $clean -replace '\[\[([^\]]+)\]\]', '$1'   # wikilinks
$clean = $clean -replace '(?m)^>\s+', ''            # blockquotes
$clean = $clean -replace '---+', ''                 # séparateurs
# Symboles spéciaux lus littéralement par TTS
$clean = $clean -replace '\u2122', ''               # ™
$clean = $clean -replace '\u00AE', ''               # ®
$clean = $clean -replace '\u00A9', ''               # ©
$clean = $clean -replace '\u2026', '...'            # …
$clean = $clean -replace '\u2014', ', '             # — tiret cadratin
$clean = $clean -replace '\u2013', ', '             # – tiret demi-cadratin
$clean = $clean -replace '\u00AB', ''               # «
$clean = $clean -replace '\u00BB', ''               # »
$clean = $clean -replace '[~^]', ''                 # tilde, caret
# Chemins de fichiers et URLs (illisibles à l'oral)
$clean = $clean -replace '[A-Za-z]:\\[\w\\./\- ]+', ''          # chemins Windows
$clean = $clean -replace '/[\w./\-]+(?:/[\w./\-]+)+', ''        # chemins Unix
$clean = $clean -replace 'https?://\S+', ''                     # URLs
# Backticks isolés restants
$clean = $clean -replace '`', ''
$clean = $clean -replace '\n{3,}', "`n`n"           # excès de newlines
$clean = $clean.Trim()

if (-not $clean) { exit 0 }

# Aplatir en une ligne
$flat = ($clean -replace '\n+', ' ').Trim()

# Extraire le résumé selon le mode
if ($mode -eq "coach") {
    $summary = $flat
} else {
    $maxLen = if ($mode -eq "detail") { 600 } else { 250 }
    $sentences = [regex]::Matches($flat, '[^.!?]+[.!?]+')
    $summary = ""
    foreach ($s in $sentences) {
        if (($summary + $s.Value).Length -gt $maxLen) { break }
        $summary += $s.Value.Trim() + " "
    }
    $summary = $summary.Trim()
    if (-not $summary) { $summary = $flat.Substring(0, [Math]::Min($flat.Length, $maxLen)) }
}

if (-not $summary) { exit 0 }

# Parler
. "$PSScriptRoot\_speak.ps1"
Invoke-JarvisSpeak $summary

exit 0
