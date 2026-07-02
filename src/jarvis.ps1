# jarvis.ps1 — Commande de controle Jarvis (Windows)
# Usage : jarvis <commande> [argument]

param(
    [string]$Command = "",
    [string]$Argument = ""
)

$ConfPath = "$env:USERPROFILE\.claude\jarvis.conf"

function Get-JarvisValue {
    param($Key)
    if (-not (Test-Path $ConfPath)) { return "" }
    $line = Get-Content $ConfPath | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) { return ($line -split "=", 2)[1].Trim() }
    return ""
}

function Set-JarvisValue {
    param($Key, $Value)
    if (-not (Test-Path $ConfPath)) { New-Item -Force -Path $ConfPath | Out-Null }
    $content = Get-Content $ConfPath -ErrorAction SilentlyContinue
    $found = $false
    $newContent = @()
    foreach ($line in $content) {
        if ($line -match "^$Key=") {
            $newContent += "$Key=$Value"
            $found = $true
        } else {
            $newContent += $line
        }
    }
    if (-not $found) { $newContent += "$Key=$Value" }
    Set-Content -Path $ConfPath -Value $newContent
}

function Resolve-Voice {
    param($Name)
    switch ($Name.ToLower()) {
        "henri"  { return "fr-FR-HenriNeural" }
        "denise" { return "fr-FR-DeniseNeural" }
        "remy"   { return "fr-FR-RemyMultilingualNeural" }
        "eloise" { return "fr-FR-EloiseNeural" }
        default  { return $Name }
    }
}

function Play-TestVoice {
    param($Voice, $Rate)
    $TmpFile = "$env:TEMP\jarvis_test.mp3"
    try {
        $ttsArgs = @("--voice", $Voice, "--text", "Bonjour, je suis maintenant votre voix.", "--write-media", $TmpFile)
        if ($Rate) { $ttsArgs += @("--rate", $Rate) }
        & edge-tts @ttsArgs 2>$null
        Add-Type -AssemblyName presentationCore
        $mp = [System.Windows.Media.MediaPlayer]::new()
        $mp.Open([uri]::new($TmpFile))
        $mp.Play()
        Start-Sleep -Seconds 5
        $mp.Close()
        Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  (test vocal echoue - verifie ta connexion internet)"
    }
}

switch ($Command.ToLower()) {

    "on" {
        Set-JarvisValue "JARVIS_ENABLED" "true"
        Write-Host "Jarvis active."
    }

    "off" {
        Set-JarvisValue "JARVIS_ENABLED" "false"
        Write-Host "Jarvis desactive."
    }

    { $_ -in "voix", "voice" } {
        if (-not $Argument) { Write-Host "Usage : jarvis voix <henri|denise|remy|eloise>"; exit 1 }
        $voice = Resolve-Voice $Argument
        Set-JarvisValue "JARVIS_VOICE" $voice
        Write-Host "Voix changee : $voice"
        Write-Host "Test en cours..."
        $rate = Get-JarvisValue "JARVIS_RATE"
        if (-not $rate) { $rate = "+25%" }
        Play-TestVoice $voice $rate
    }

    "mode" {
        if ($Argument -notin @("court", "detail", "coach")) {
            Write-Host "Mode inconnu. Choix : court, detail, coach"; exit 1
        }
        Set-JarvisValue "JARVIS_MODE" $Argument
        Write-Host "Mode change : $Argument"
        if ($Argument -eq "coach") {
            Set-JarvisValue "JARVIS_TRANSCRIPT" "true"
            Write-Host "Transcript active (mode coach)."
            Set-Content -Path "$env:TEMP\jarvis-coach-transcript.jsonl" -Value ""
            Write-Host "Fichier transcript reinitialise."
        }
    }

    "coach" {
        Set-JarvisValue "JARVIS_ENABLED" "true"
        Set-JarvisValue "JARVIS_MODE" "coach"
        Set-JarvisValue "JARVIS_TRANSCRIPT" "true"
        Set-Content -Path "$env:TEMP\jarvis-coach-transcript.jsonl" -Value ""
        Write-Host ""
        Write-Host "  Mode Coach IA active"
        Write-Host "  --------------------"
        Write-Host "  Jarvis lit les reponses completes."
        Write-Host "  Transcript active."
        Write-Host ""
        Write-Host "  Pour revenir en mode normal : jarvis mode court"
        Write-Host ""
    }

    { $_ -in "shut", "stop", "tais-toi", "silence" } {
        Set-Content -Path "$env:TEMP\jarvis-stop" -Value ""
        Get-Process -Name "powershell" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*MediaPlayer*jarvis*" } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process -Name "edge-tts" -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\jarvis_*.mp3" -Force -ErrorAction SilentlyContinue
        Write-Host "Jarvis coupe."
    }

    { $_ -in "rate", "vitesse", "debit" } {
        if (-not $Argument) { Write-Host "Usage : jarvis rate <+10%|+25%|+40%|+50%>"; exit 1 }
        if ($Argument -notmatch '^[+-]\d+%$') {
            Write-Host "Format invalide. Exemples : +25%, +40%, -10%"
            exit 1
        }
        Set-JarvisValue "JARVIS_RATE" $Argument
        Write-Host "Debit change : $Argument"
        Write-Host "Test en cours..."
        $voice = Get-JarvisValue "JARVIS_VOICE"
        if (-not $voice) { $voice = "fr-FR-HenriNeural" }
        Play-TestVoice $voice $Argument
    }

    "transcript" {
        switch ($Argument.ToLower()) {
            "on" {
                Set-JarvisValue "JARVIS_TRANSCRIPT" "true"
                Write-Host "Transcript active."
            }
            "off" {
                Set-JarvisValue "JARVIS_TRANSCRIPT" "false"
                Write-Host "Transcript desactive."
            }
            "show" {
                $logFile = "$env:TEMP\jarvis-coach-transcript.jsonl"
                if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 0) {
                    Write-Host ""
                    Write-Host "  Transcript courant :"
                    Write-Host "  --------------------"
                    foreach ($line in Get-Content $logFile) {
                        if (-not $line.Trim()) { continue }
                        try {
                            $entry = $line | ConvertFrom-Json
                            $ts = $entry.timestamp.Substring(0, 19).Replace("T", " ")
                            $role = $entry.role
                            $text = if ($entry.text.Length -gt 100) { $entry.text.Substring(0, 100) } else { $entry.text }
                            Write-Host "  [$ts] ${role}: ${text}..."
                        } catch {}
                    }
                    Write-Host ""
                } else {
                    Write-Host "Pas de transcript en cours."
                }
            }
            "clear" {
                Set-Content -Path "$env:TEMP\jarvis-coach-transcript.jsonl" -Value ""
                Write-Host "Transcript efface."
            }
            default {
                Write-Host "Usage : jarvis transcript <on|off|show|clear>"
                exit 1
            }
        }
    }

    "remote" {
        switch ($Argument.ToLower()) {
            "on"  { Set-JarvisValue "JARVIS_REMOTE" "true";  Write-Host "Mode remote active — son sur iPhone uniquement" }
            "off" { Set-JarvisValue "JARVIS_REMOTE" "false"; Write-Host "Mode remote desactive — son local" }
            default { Write-Host "Usage : jarvis remote on|off" }
        }
    }

    "telegram" {
        switch ($Argument.ToLower()) {
            "on" {
                $token = Get-JarvisValue "JARVIS_TELEGRAM_TOKEN"
                $chatId = Get-JarvisValue "JARVIS_TELEGRAM_CHAT_ID"
                if (-not $token -or -not $chatId) {
                    Write-Host ""
                    Write-Host "  Configuration Telegram requise."
                    Write-Host ""
                    Write-Host "  1. Cree un bot via @BotFather sur Telegram"
                    Write-Host "  2. Recupere le token du bot"
                    Write-Host "  3. Envoie un message au bot puis recupere ton chat_id"
                    Write-Host "     (via https://api.telegram.org/bot<TOKEN>/getUpdates)"
                    Write-Host ""
                    $token = Read-Host "  Token du bot"
                    $chatId = Read-Host "  Chat ID"
                    if (-not $token -or -not $chatId) { Write-Host "Annule."; exit 1 }
                    Set-JarvisValue "JARVIS_TELEGRAM_TOKEN" $token
                    Set-JarvisValue "JARVIS_TELEGRAM_CHAT_ID" $chatId
                }
                Set-JarvisValue "JARVIS_TELEGRAM" "true"
                Write-Host "Mode Telegram active — reponses vocales envoyees sur Telegram"
                # Test
                $sendScript = "$env:USERPROFILE\.local\bin\jarvis-telegram-send.ps1"
                if (Test-Path $sendScript) {
                    try {
                        & powershell -NoProfile -ExecutionPolicy Bypass -File $sendScript -Text "Mode Telegram active." 2>$null
                        Write-Host "Test envoye sur Telegram."
                    } catch {
                        Write-Host "Erreur d'envoi."
                    }
                } else {
                    Write-Host "  (script jarvis-telegram-send non trouve — relance l'installateur)"
                }
            }
            "off" {
                Set-JarvisValue "JARVIS_TELEGRAM" "false"
                Write-Host "Mode Telegram desactive."
            }
            default { Write-Host "Usage : jarvis telegram on|off" }
        }
    }

    "notify" {
        switch ($Argument.ToLower()) {
            "on"  { Set-JarvisValue "JARVIS_NOTIFY" "true";  Write-Host "Notification active — Jarvis dit 'j'ai besoin de toi' quand l'IA demande une permission" }
            "off" { Set-JarvisValue "JARVIS_NOTIFY" "false"; Write-Host "Notification desactivee — plus de 'j'ai besoin de toi'" }
            default { Write-Host "Usage : jarvis notify on|off" }
        }
    }

    "status" {
        Write-Host ""
        Write-Host "  Jarvis — configuration actuelle"
        Write-Host "  --------------------------------"
        Write-Host ("  {0,-14} {1}" -f "Active :",     (Get-JarvisValue "JARVIS_ENABLED"))
        Write-Host ("  {0,-14} {1}" -f "Mode :",       (Get-JarvisValue "JARVIS_MODE"))
        Write-Host ("  {0,-14} {1}" -f "Voix :",       (Get-JarvisValue "JARVIS_VOICE"))
        Write-Host ("  {0,-14} {1}" -f "Debit :",      (Get-JarvisValue "JARVIS_RATE"))
        $notifyVal = Get-JarvisValue "JARVIS_NOTIFY"; if (-not $notifyVal) { $notifyVal = "true (defaut)" }
        Write-Host ("  {0,-14} {1}" -f "Notify :",     $notifyVal)
        Write-Host ("  {0,-14} {1}" -f "Remote :",     (Get-JarvisValue "JARVIS_REMOTE"))
        Write-Host ("  {0,-14} {1}" -f "Telegram :",   (Get-JarvisValue "JARVIS_TELEGRAM"))
        Write-Host ("  {0,-14} {1}" -f "Transcript :", (Get-JarvisValue "JARVIS_TRANSCRIPT"))
        $logFile = "$env:TEMP\jarvis-coach-transcript.jsonl"
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 0) {
            $lines = (Get-Content $logFile | Where-Object { $_.Trim() }).Count
            Write-Host ("  {0,-14} {1} echanges" -f "Log :", $lines)
        }
        Write-Host ""
    }

    { $_ -in "aide", "help", "" } {
        Write-Host ""
        Write-Host "  Usage : jarvis <commande> [argument]"
        Write-Host ""
        Write-Host "  jarvis on              Activer le feedback vocal"
        Write-Host "  jarvis off             Desactiver le feedback vocal"
        Write-Host "  jarvis shut            Couper la lecture en cours"
        Write-Host "  jarvis voix <nom>      Changer la voix (teste immediatement)"
        Write-Host "    Voix disponibles : henri, denise, remy, eloise"
        Write-Host "  jarvis mode court      Resume court (2-3 phrases)"
        Write-Host "  jarvis mode detail     Resume detaille"
        Write-Host "  jarvis mode coach      Lit les reponses completes + transcript"
        Write-Host "  jarvis coach           Raccourci : active tout le mode coach"
        Write-Host "  jarvis rate <+XX%>     Changer le debit (ex: +25%, +40%)"
        Write-Host "  jarvis transcript on   Activer le log de conversation"
        Write-Host "  jarvis transcript off  Desactiver le log de conversation"
        Write-Host "  jarvis transcript show Afficher le transcript courant"
        Write-Host "  jarvis transcript clear Effacer le transcript"
        Write-Host "  jarvis notify on|off   Activer/couper le 'j'ai besoin de toi' (permissions)"
        Write-Host "  jarvis remote on|off   Son sur iPhone uniquement (via stream)"
        Write-Host "  jarvis telegram on|off Reponses vocales envoyees sur Telegram"
        Write-Host "  jarvis status          Voir la configuration actuelle"
        Write-Host ""
    }

    default {
        Write-Host "Commande inconnue : $Command"
        Write-Host "Tape 'jarvis aide' pour voir les commandes."
        exit 1
    }
}
