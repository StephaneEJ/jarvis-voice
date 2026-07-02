# jarvis-telegram-send.ps1 — Envoie un message texte ou vocal sur Telegram
# Usage :
#   jarvis-telegram-send.ps1 -Text "Message"
#   jarvis-telegram-send.ps1 -Voice "C:\chemin\fichier.mp3" [-Caption "texte"]

param(
    [string]$Text = "",
    [string]$Voice = "",
    [string]$Audio = "",
    [string]$Caption = ""
)

$ConfPath = "$env:USERPROFILE\.claude\jarvis.conf"

function Get-ConfValue {
    param($Key)
    if (-not (Test-Path $ConfPath)) { return "" }
    $line = Get-Content $ConfPath | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) { return ($line -split "=", 2)[1].Trim() }
    return ""
}

$Token = Get-ConfValue "JARVIS_TELEGRAM_TOKEN"
$ChatId = Get-ConfValue "JARVIS_TELEGRAM_CHAT_ID"

if (-not $Token -or -not $ChatId) {
    Write-Error "JARVIS_TELEGRAM_TOKEN ou JARVIS_TELEGRAM_CHAT_ID non configure. Lance 'jarvis telegram on'."
    exit 1
}

$Api = "https://api.telegram.org/bot$Token"

# Mode vocal
if ($Voice) {
    if (-not (Test-Path $Voice)) { Write-Error "Fichier introuvable : $Voice"; exit 1 }
    $boundary = [System.Guid]::NewGuid().ToString()
    $fileBytes = [System.IO.File]::ReadAllBytes($Voice)
    $fileName = [System.IO.Path]::GetFileName($Voice)
    $bodyLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"chat_id`"",
        "",
        $ChatId,
        "--$boundary",
        "Content-Disposition: form-data; name=`"voice`"; filename=`"$fileName`"",
        "Content-Type: audio/ogg",
        ""
    )
    $bodyStart = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join "`r`n") + "`r`n")
    $bodyEnd = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
    $body = $bodyStart + $fileBytes + $bodyEnd
    try {
        Invoke-RestMethod -Uri "$Api/sendVoice" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
    } catch {}
    exit 0
}

# Mode audio
if ($Audio) {
    if (-not (Test-Path $Audio)) { Write-Error "Fichier introuvable : $Audio"; exit 1 }
    $boundary = [System.Guid]::NewGuid().ToString()
    $fileBytes = [System.IO.File]::ReadAllBytes($Audio)
    $fileName = [System.IO.Path]::GetFileName($Audio)
    $bodyLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"chat_id`"",
        "",
        $ChatId,
        "--$boundary",
        "Content-Disposition: form-data; name=`"audio`"; filename=`"$fileName`"",
        "Content-Type: audio/mpeg",
        ""
    )
    $bodyStart = [System.Text.Encoding]::UTF8.GetBytes(($bodyLines -join "`r`n") + "`r`n")
    $bodyEnd = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
    $body = $bodyStart + $fileBytes + $bodyEnd
    try {
        Invoke-RestMethod -Uri "$Api/sendAudio" -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
    } catch {}
    exit 0
}

# Mode texte
if (-not $Text) {
    # Accepter aussi les arguments positionnels
    if ($args.Count -gt 0) { $Text = $args -join " " }
}
if (-not $Text) { Write-Error "Usage : jarvis-telegram-send.ps1 -Text `"message`""; exit 1 }

try {
    $body = @{ chat_id = $ChatId; text = $Text } | ConvertTo-Json
    Invoke-RestMethod -Uri "$Api/sendMessage" -Method Post -ContentType "application/json" -Body $body | Out-Null
} catch {}
exit 0
