# _speak.ps1 — Fonction TTS partagee par les hooks Jarvis (Windows)
# Usage : . "$PSScriptRoot\_speak.ps1"; Invoke-JarvisSpeak "Texte"

function Get-JarvisConfig {
    $conf = @{
        JARVIS_VOICE    = "fr-FR-DeniseNeural"
        JARVIS_RATE     = "+25%"
        JARVIS_REMOTE   = "false"
        JARVIS_TELEGRAM = "false"
    }
    $confPath = "$env:USERPROFILE\.claude\jarvis.conf"
    if (Test-Path $confPath) {
        foreach ($line in Get-Content $confPath) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith("#")) { continue }
            $idx = $t.IndexOf("=")
            if ($idx -gt 0) {
                $k = $t.Substring(0, $idx).Trim()
                $v = $t.Substring($idx + 1).Trim()
                $conf[$k] = $v
            }
        }
    }
    return $conf
}

function Send-TelegramVoice {
    param([string]$FilePath)
    $conf = Get-JarvisConfig
    if ($conf["JARVIS_TELEGRAM"] -ne "true") { return }
    $sendScript = "$env:USERPROFILE\.local\bin\jarvis-telegram-send.ps1"
    if ((Test-Path $sendScript) -and (Test-Path $FilePath)) {
        Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $sendScript, "-Voice", $FilePath -WindowStyle Hidden
    }
}

function Invoke-JarvisSpeak {
    param([string]$Text)
    if (-not $Text) { return }

    $conf = Get-JarvisConfig
    $voice = $conf["JARVIS_VOICE"]
    if (-not $voice) { $voice = "fr-FR-DeniseNeural" }
    $rate = $conf["JARVIS_RATE"]
    if (-not $rate) { $rate = "+25%" }

    $tmpFile = "$env:TEMP\jarvis_$(Get-Date -Format 'yyyyMMddHHmmssfff').mp3"

    # 1. Edge TTS : generer le MP3
    $pythonExe = $null
    $winPythonPaths = @(
        "$env:USERPROFILE\WinPython\WPy64-312101\python\python.exe",
        "$env:USERPROFILE\WinPython\python\python.exe"
    )
    foreach ($p in $winPythonPaths) {
        if (Test-Path $p) { $pythonExe = $p; break }
    }
    if (-not $pythonExe) {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -notlike "*WindowsApps*") { $pythonExe = $cmd.Source }
    }

    # Ecrire le texte dans un fichier temp UTF-8
    $txtFile = "$env:TEMP\jarvis_text_$(Get-Date -Format 'yyyyMMddHHmmssfff').txt"
    [System.IO.File]::WriteAllText($txtFile, $Text, [System.Text.UTF8Encoding]::new($false))

    $ttsOk = $false
    try {
        if ($pythonExe) {
            & $pythonExe -m edge_tts --voice $voice --rate $rate -f $txtFile --write-media $tmpFile 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpFile) -and (Get-Item $tmpFile).Length -gt 0) { $ttsOk = $true }
        }
        if (-not $ttsOk) {
            $edgeCmd = Get-Command edge-tts -ErrorAction SilentlyContinue
            if ($edgeCmd) {
                & edge-tts --voice $voice --rate $rate -f $txtFile --write-media $tmpFile 2>$null
                if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpFile) -and (Get-Item $tmpFile).Length -gt 0) { $ttsOk = $true }
            }
        }
    } catch {}
    Remove-Item $txtFile -Force -ErrorAction SilentlyContinue

    # 2. Lire le MP3 + envoyer sur Telegram si active
    if ($ttsOk) {
        # Telegram en parallele
        Send-TelegramVoice $tmpFile

        $resolvedPath = (Resolve-Path $tmpFile).Path
        $playScript = "$env:TEMP\jarvis_play_$([System.IO.Path]::GetRandomFileName()).ps1"
        @"
Add-Type -AssemblyName presentationCore
`$player = New-Object System.Windows.Media.MediaPlayer
`$player.Open([uri]::new('$resolvedPath'))
Start-Sleep -Milliseconds 300
`$player.Play()
`$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
`$timer = New-Object System.Windows.Threading.DispatcherTimer
`$timer.Interval = [TimeSpan]::FromMilliseconds(200)
`$tick = 0
`$timer.Add_Tick({
    `$script:tick++
    if (`$player.NaturalDuration.HasTimeSpan -and `$player.Position -ge `$player.NaturalDuration.TimeSpan) {
        `$player.Close()
        `$dispatcher.InvokeShutdown()
    }
    if (`$script:tick -gt 150) { `$dispatcher.InvokeShutdown() }
})
`$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
Remove-Item '$resolvedPath' -Force -ErrorAction SilentlyContinue
Remove-Item '$playScript' -Force -ErrorAction SilentlyContinue
"@ | Set-Content -Path $playScript -Encoding UTF8

        # VBScript wrapper : lance PowerShell sans fenetre visible
        $vbsLauncher = "$env:TEMP\jarvis_launch_$([System.IO.Path]::GetRandomFileName()).vbs"
        @"
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$playScript""", 0, True
CreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName
"@ | Set-Content -Path $vbsLauncher -Encoding ASCII
        Start-Process -FilePath "wscript.exe" -ArgumentList $vbsLauncher -Wait -WindowStyle Hidden
        return
    }

    # 3. Fallback : System.Speech (natif Windows)
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    try {
        Add-Type -AssemblyName System.Speech
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try {
            $synth.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Female, [System.Speech.Synthesis.VoiceAge]::Adult, 0, [System.Globalization.CultureInfo]::new("fr-FR"))
        } catch {
            try { $synth.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Female) } catch {}
        }
        $synth.Speak($Text)
        $synth.Dispose()
    } catch {}
}
