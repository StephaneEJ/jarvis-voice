# voice-post-tool.ps1 — Hook PostToolUseFailure Claude Code (Windows)
# Annonce vocalement les erreurs d'outils.

# Vérifier si Jarvis est activé
$confPath = "$env:USERPROFILE\.claude\jarvis.conf"
$enabled = "false"
if (Test-Path $confPath) {
    $line = Get-Content $confPath | Where-Object { $_ -match "^JARVIS_ENABLED=" } | Select-Object -First 1
    if ($line) { $enabled = ($line -split "=", 2)[1].Trim() }
}
if ($enabled -ne "true") { exit 0 }

# Lire stdin JSON
$inputText = [Console]::In.ReadToEnd()

$msg = "Attention, une erreur a été détectée."
try {
    $data = $inputText | ConvertFrom-Json
    $tool = if ($data.tool_name) { $data.tool_name } else { "outil inconnu" }
    $error = if ($data.error) { $data.error } else { "" }
    $lines = ($error -split "`n") | Where-Object { $_.Trim() } | Select-Object -Last 1
    $detail = if ($lines) { $lines.Substring(0, [Math]::Min($lines.Length, 80)) } else { "erreur inconnue" }
    $msg = "Attention, erreur sur $tool. $detail"
} catch {}

# Parler
. "$PSScriptRoot\_speak.ps1"
Invoke-JarvisSpeak $msg

exit 0
