# voice-notification.ps1 — Hook Notification Claude Code (Windows)
# Interpelle l'utilisateur quand Claude Code a besoin d'une confirmation.

# Vérifier si Jarvis est activé
$confPath = "$env:USERPROFILE\.claude\jarvis.conf"
$enabled = "false"
if (Test-Path $confPath) {
    $line = Get-Content $confPath | Where-Object { $_ -match "^JARVIS_ENABLED=" } | Select-Object -First 1
    if ($line) { $enabled = ($line -split "=", 2)[1].Trim() }
}
if ($enabled -ne "true") { exit 0 }

# Toggle dédié : JARVIS_NOTIFY=false → silencieux. Absent/true → parle (défaut).
# Pilotable via : jarvis notify on|off
$notify = "true"
if (Test-Path $confPath) {
    $nline = Get-Content $confPath | Where-Object { $_ -match "^JARVIS_NOTIFY=" } | Select-Object -First 1
    if ($nline) { $notify = ($nline -split "=", 2)[1].Trim() }
}
if ($notify -eq "false") { exit 0 }

# Parler
. "$PSScriptRoot\_speak.ps1"
Invoke-JarvisSpeak "j'ai besoin de toi"

exit 0
