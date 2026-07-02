# install.ps1 — Installateur Jarvis pour Windows
# Supporte OpenCode + Claude Code
# Usage : clic droit -> "Exécuter avec PowerShell"
# Ou depuis un terminal : powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "`n>>> $msg" -ForegroundColor Yellow }
function Write-Ok    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Add-Utf8Bom {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($true))
}

# Voix par défaut Windows
$DefaultVoice = "fr-FR-DeniseNeural"

Write-Host ""
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host "  |   Installation de Jarvis Voice v2.1           |" -ForegroundColor Cyan
Write-Host "  |   Feedback vocal OpenCode + Claude Code       |" -ForegroundColor Cyan
Write-Host "  |   + Mode Telegram                             |" -ForegroundColor Cyan
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host "  Plateforme : Windows"
Write-Host ""

# --- Vérifications ---
Write-Step "Verification des prerequis"

# Chercher Python : WinPython portable, puis python sur PATH (ignorer le stub WindowsApps)
$PythonExe = $null
$winPythonPaths = @(
    "$env:USERPROFILE\WinPython\WPy64-312101\python\python.exe",
    "$env:USERPROFILE\WinPython\python\python.exe"
)
foreach ($p in $winPythonPaths) {
    if (Test-Path $p) { $PythonExe = $p; break }
}
if (-not $PythonExe) {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*WindowsApps*") { $PythonExe = $cmd.Source }
}

if ($PythonExe) {
    $pyVer = & $PythonExe --version 2>&1
    Write-Ok "Python trouve : $pyVer ($PythonExe)"
} else {
    Write-Warn "Python non trouve"
    Write-Host ""
    Write-Host "  Sans Python, Jarvis utilisera la voix de secours Windows (System.Speech)."
    Write-Host "  La voix sera fonctionnelle mais robotique."
    Write-Host ""
    Write-Host "  Pour la voix naturelle (Edge TTS), il faut Python."
    Write-Host "  Deux options :"
    Write-Host ""

    # Détecter si on a les droits admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($isAdmin) {
        Write-Host "    1. Installer Python depuis python.org (droits admin detectes)"
        Write-Host "    2. Telecharger WinPython portable (pas besoin d'admin, ~200 Mo)"
        Write-Host "    3. Continuer sans Python (voix de secours)"
    } else {
        Write-Host "    1. Telecharger WinPython portable (pas besoin d'admin, ~200 Mo)"
        Write-Host "    2. Continuer sans Python (voix de secours)"
        Write-Host ""
        Write-Host "    Note : l'installation classique de Python necessite les droits"
        Write-Host "    administrateur. WinPython est recommande pour les utilisateurs"
        Write-Host "    sans droits admin."
    }
    Write-Host ""

    $choice = Read-Host "  Choix (numero)"

    $installPython = $false
    $installWinPython = $false

    if ($isAdmin) {
        switch ($choice) {
            "1" { $installPython = $true }
            "2" { $installWinPython = $true }
        }
    } else {
        if ($choice -eq "1") { $installWinPython = $true }
    }

    if ($installWinPython) {
        Write-Step "Telechargement de WinPython portable"
        $wpVersion = "3.12.10.1"
        $wpFileName = "Winpython64-${wpVersion}dot.exe"
        $wpUrl = "https://github.com/winpython/winpython/releases/download/12.2025-03/$wpFileName"
        $wpDownload = "$env:TEMP\$wpFileName"
        $wpDest = "$env:USERPROFILE\WinPython"

        Write-Host "  Telechargement depuis GitHub (~200 Mo)..."
        Write-Host "  URL : $wpUrl"
        try {
            # Utiliser BITS pour le téléchargement (plus fiable, affiche la progression)
            $bitsOk = $false
            try {
                Start-BitsTransfer -Source $wpUrl -Destination $wpDownload -DisplayName "WinPython" -Description "Telechargement en cours..."
                $bitsOk = $true
            } catch {
                # Fallback sur Invoke-WebRequest si BITS échoue
                Write-Host "  (BITS indisponible, utilisation du telechargement classique...)"
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $wpUrl -OutFile $wpDownload -UseBasicParsing
            }

            if (Test-Path $wpDownload) {
                $dlSize = [math]::Round((Get-Item $wpDownload).Length / 1MB, 1)
                Write-Ok "Telecharge ($dlSize Mo)"

                Write-Host "  Extraction en cours (peut prendre 1-2 minutes)..."
                New-Item -ItemType Directory -Force -Path $wpDest | Out-Null
                # WinPython .exe est un auto-extracteur 7-Zip
                Start-Process -FilePath $wpDownload -ArgumentList "-o`"$wpDest`"", "-y" -Wait -WindowStyle Hidden
                Remove-Item $wpDownload -Force -ErrorAction SilentlyContinue

                # Trouver le python.exe dans le dossier extrait
                $extracted = Get-ChildItem $wpDest -Directory | Select-Object -First 1
                if ($extracted) {
                    $possiblePython = Join-Path $extracted.FullName "python\python.exe"
                    if (Test-Path $possiblePython) {
                        $PythonExe = $possiblePython
                        $pyVer = & $PythonExe --version 2>&1
                        Write-Ok "WinPython installe : $pyVer ($PythonExe)"
                    } else {
                        # Chercher récursivement
                        $found = Get-ChildItem $wpDest -Recurse -Filter "python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($found) {
                            $PythonExe = $found.FullName
                            $pyVer = & $PythonExe --version 2>&1
                            Write-Ok "WinPython installe : $pyVer ($PythonExe)"
                        } else {
                            Write-Warn "Extraction reussie mais python.exe non trouve dans $wpDest"
                        }
                    }
                }
            } else {
                Write-Warn "Telechargement echoue"
            }
        } catch {
            Write-Warn "Erreur lors du telechargement : $_"
            Write-Host "  Tu peux telecharger WinPython manuellement :"
            Write-Host "    https://github.com/winpython/winpython/releases"
            Write-Host "  Extrais-le dans : $wpDest"
        }
    }
    elseif ($installPython) {
        Write-Step "Installation de Python"
        Write-Host "  Telechargement de Python 3.12..."
        $pyInstaller = "$env:TEMP\python-installer.exe"
        $pyUrl = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $pyUrl -OutFile $pyInstaller -UseBasicParsing
            Write-Host "  Installation silencieuse en cours..."
            Start-Process -FilePath $pyInstaller -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1" -Wait
            Remove-Item $pyInstaller -Force -ErrorAction SilentlyContinue
            # Recharger le PATH
            $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [Environment]::GetEnvironmentVariable("PATH", "User")
            $cmd = Get-Command python -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Source -notlike "*WindowsApps*") {
                $PythonExe = $cmd.Source
                $pyVer = & $PythonExe --version 2>&1
                Write-Ok "Python installe : $pyVer"
            } else {
                Write-Warn "Python installe mais non detecte — redémarre ton terminal après l'installation"
            }
        } catch {
            Write-Warn "Erreur lors de l'installation : $_"
            Write-Host "  Telecharge Python manuellement : https://www.python.org/downloads/"
        }
    }
    else {
        Write-Host "  OK, on continue avec la voix de secours."
    }
}

$HasOpenCode = $false
$HasClaudeCode = $false
if (Get-Command opencode -ErrorAction SilentlyContinue) { $HasOpenCode = $true }
if (Test-Path "$env:USERPROFILE\.claude") { $HasClaudeCode = $true }

if ($HasOpenCode) { Write-Ok "OpenCode detecte" } else { Write-Warn "OpenCode non trouve" }
if ($HasClaudeCode) { Write-Ok "Claude Code detecte" } else { Write-Warn "Claude Code non detecte" }

# --- Installation edge-tts ---
Write-Step "Installation de Edge TTS"

$edgeInstalled = $false
if ($PythonExe) {
    try {
        $result = & $PythonExe -c "import edge_tts; print('ok')" 2>$null
        if ($result -eq "ok") { $edgeInstalled = $true }
    } catch {}
}

if ($edgeInstalled) {
    Write-Ok "edge-tts deja installe"
} else {
    if ($PythonExe) {
        Write-Host "  Installation via pip..."
        try {
            & $PythonExe -m pip install edge-tts --quiet 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "edge-tts installe"
            } else {
                Write-Warn "edge-tts non installe - la voix de secours Windows (System.Speech) sera utilisee"
            }
        } catch {
            Write-Warn "edge-tts non installe - la voix de secours Windows (System.Speech) sera utilisee"
        }
    } else {
        Write-Warn "Pas de Python - la voix de secours Windows (System.Speech) sera utilisee"
    }
}

# --- Configuration commune ---
Write-Step "Configuration de base"

$ClaudeDir = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$ConfDest = "$ClaudeDir\jarvis.conf"
if (Test-Path $ConfDest) {
    Write-Warn "jarvis.conf existant conservé (pas écrasé)"
    # Ajouter les nouvelles clés si absentes
    $content = Get-Content $ConfDest -Raw
    if ($content -notmatch "JARVIS_RATE=") {
        Add-Content $ConfDest "JARVIS_RATE=+25%"
    }
    if ($content -notmatch "JARVIS_TRANSCRIPT=") {
        Add-Content $ConfDest "JARVIS_TRANSCRIPT=false"
    }
    if ($content -notmatch "JARVIS_REMOTE=") {
        Add-Content $ConfDest "JARVIS_REMOTE=false"
    }
    if ($content -notmatch "JARVIS_TELEGRAM=") {
        Add-Content $ConfDest "JARVIS_TELEGRAM=false"
    }
    Write-Ok "Nouvelles cles ajoutees si absentes"
} else {
    Copy-Item "$ScriptDir\src\jarvis.conf" $ConfDest
    # Voix par défaut Windows : Denise
    (Get-Content $ConfDest) -replace "JARVIS_VOICE=.*", "JARVIS_VOICE=$DefaultVoice" | Set-Content $ConfDest
    Write-Ok "Config installée dans $ConfDest (voix : Denise)"
}

# --- Installation de la commande jarvis ---
Write-Step "Installation de la commande 'jarvis'"

$BinDir = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item "$ScriptDir\src\jarvis.ps1" "$BinDir\jarvis.ps1" -Force
Add-Utf8Bom "$BinDir\jarvis.ps1"

# Installer jarvis-telegram-send
Copy-Item "$ScriptDir\src\jarvis-telegram-send.ps1" "$BinDir\jarvis-telegram-send.ps1" -Force
Add-Utf8Bom "$BinDir\jarvis-telegram-send.ps1"

# Wrapper .cmd
$WrapperContent = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%USERPROFILE%\.local\bin\jarvis.ps1`" %*"
Set-Content -Path "$BinDir\jarvis.cmd" -Value $WrapperContent
Write-Ok "Commandes installees dans $BinDir (jarvis + jarvis-telegram-send)"

# Ajout au PATH utilisateur
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$BinDir", "User")
    Write-Warn "PATH mis à jour — relance ton terminal pour que 'jarvis' soit disponible"
}
$env:PATH += ";$BinDir"

# ===================================================
# SECTION OPENCODE
# ===================================================
Write-Step "Configuration d'OpenCode"

# OpenCode utilise ~/.config/opencode/plugins/ sur tous les OS
$OpenCodePlugins = "$env:USERPROFILE\.config\opencode\plugins"
New-Item -ItemType Directory -Force -Path $OpenCodePlugins | Out-Null
Copy-Item "$ScriptDir\src\jarvis.js" "$OpenCodePlugins\jarvis.js" -Force
Write-Ok "Plugin installé dans $OpenCodePlugins\jarvis.js"

# ===================================================
# SECTION CLAUDE CODE
# ===================================================
if (Test-Path "$env:USERPROFILE\.claude") {
    Write-Step "Configuration de Claude Code"

    $HooksDir = "$env:USERPROFILE\.claude\hooks"
    New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

    # Copier les hooks PowerShell
    foreach ($hook in @("_speak.ps1", "voice-post-tool.ps1", "voice-notification.ps1", "voice-stop.ps1")) {
        Copy-Item "$ScriptDir\src\claude-hooks\$hook" "$HooksDir\$hook" -Force
        Add-Utf8Bom "$HooksDir\$hook"
    }
    Write-Ok "Hooks installés dans $HooksDir\"

    # Merger settings.json
    $SettingsPath = "$env:USERPROFILE\.claude\settings.json"
    $settings = @{}
    if (Test-Path $SettingsPath) {
        try {
            $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            $settings = @{}
        }
    }

    if (-not $settings.ContainsKey("hooks")) { $settings["hooks"] = @{} }

    # Format nested requis par Claude Code : { matcher, hooks: [{ type, command }] }
    $hooksConfig = @{
        "PostToolUseFailure" = @{
            matcher = ""
            hooks = @(
                @{ type = "command"; command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HooksDir\voice-post-tool.ps1`"" }
            )
        }
        "Notification" = @{
            matcher = ""
            hooks = @(
                @{ type = "command"; command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HooksDir\voice-notification.ps1`"" }
            )
        }
        "Stop" = @{
            matcher = ""
            hooks = @(
                @{ type = "command"; command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HooksDir\voice-stop.ps1`"" }
            )
        }
    }

    foreach ($event in $hooksConfig.Keys) {
        $newEntry = $hooksConfig[$event]
        $existing = @()
        if ($settings["hooks"].ContainsKey($event)) {
            $existing = @($settings["hooks"][$event])
        }

        # Chercher et remplacer une entrée Jarvis existante
        $found = $false
        for ($i = 0; $i -lt $existing.Count; $i++) {
            $isJarvis = $false
            # Detecter format nested existant
            if ($existing[$i] -is [hashtable] -and $existing[$i].ContainsKey("hooks")) {
                foreach ($sub in $existing[$i]["hooks"]) {
                    $subcmd = ""
                    if ($sub -is [hashtable]) { $subcmd = $sub["command"] }
                    elseif ($sub.command) { $subcmd = $sub.command }
                    if ($subcmd -like "*voice-*") { $isJarvis = $true; break }
                }
            }
            # Detecter format flat existant
            $flatCmd = ""
            if ($existing[$i] -is [hashtable]) { $flatCmd = $existing[$i]["command"] }
            elseif ($existing[$i].command) { $flatCmd = $existing[$i].command }
            if ($flatCmd -like "*voice-*") { $isJarvis = $true }

            if ($isJarvis) {
                $existing[$i] = $newEntry
                $found = $true
                break
            }
        }
        if (-not $found) { $existing += $newEntry }
        $settings["hooks"][$event] = $existing
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsPath
    Write-Ok "settings.json mis à jour (hooks Jarvis)"
}

# --- Test de la voix ---
Write-Step "Test de la voix"

Write-Host "  Connexion à Edge TTS en cours..."
$TmpFile = "$env:TEMP\jarvis_test.mp3"

# Lire la voix configurée
$testVoice = $DefaultVoice
$testRate = "+25%"
if (Test-Path $ConfDest) {
    $vLine = Get-Content $ConfDest | Where-Object { $_ -match "^JARVIS_VOICE=" } | Select-Object -First 1
    if ($vLine) { $testVoice = ($vLine -split "=", 2)[1].Trim() }
    $rLine = Get-Content $ConfDest | Where-Object { $_ -match "^JARVIS_RATE=" } | Select-Object -First 1
    if ($rLine) { $testRate = ($rLine -split "=", 2)[1].Trim() }
}

$testText = "Jarvis est maintenant installe. Bonne session de code."
$ttsTestOk = $false

try {
    if ($PythonExe) {
        & $PythonExe -m edge_tts --voice $testVoice --rate $testRate --text $testText --write-media $TmpFile 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $TmpFile) -and (Get-Item $TmpFile).Length -gt 0) { $ttsTestOk = $true }
    }
    if (-not $ttsTestOk) {
        $edgeCmd = Get-Command edge-tts -ErrorAction SilentlyContinue
        if ($edgeCmd) {
            & edge-tts --voice $testVoice --rate $testRate --text $testText --write-media $TmpFile 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $TmpFile) -and (Get-Item $TmpFile).Length -gt 0) { $ttsTestOk = $true }
        }
    }
    if ($ttsTestOk) {
        Add-Type -AssemblyName presentationCore
        $mp = [System.Windows.Media.MediaPlayer]::new()
        $mp.Open([uri]::new($TmpFile))
        $mp.Play()
        Start-Sleep -Seconds 5
        $mp.Close()
        Remove-Item $TmpFile -Force -ErrorAction SilentlyContinue
        Write-Ok "Test vocal reussi (Edge TTS)"
    } else {
        # Fallback System.Speech
        Add-Type -AssemblyName System.Speech
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        try { $synth.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Female, [System.Speech.Synthesis.VoiceAge]::Adult, 0, [System.Globalization.CultureInfo]::new("fr-FR")) } catch {}
        $synth.Speak($testText)
        $synth.Dispose()
        Write-Ok "Test vocal reussi (System.Speech fallback)"
    }
} catch {
    Write-Warn "Test vocal echoue"
}

# --- Résumé ---
Write-Host ""
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host "  |   Installation terminee !                       |" -ForegroundColor Cyan
Write-Host "  +================================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Environnements configures :"
if ($HasOpenCode) { Write-Host "    [OK] OpenCode (plugin + commande jarvis)" }
if (Test-Path "$env:USERPROFILE\.claude") { Write-Host "    [OK] Claude Code (hooks + settings.json)" }
Write-Host "    [OK] Commande jarvis-telegram-send"
Write-Host ""
Write-Host "  Commandes disponibles :"
Write-Host "    jarvis status          -> voir la configuration"
Write-Host "    jarvis off             -> couper la voix"
Write-Host "    jarvis on              -> reactiver"
Write-Host "    jarvis shut            -> couper la lecture en cours"
Write-Host "    jarvis voix denise     -> changer de voix"
Write-Host "    jarvis rate +40%       -> changer le debit"
Write-Host "    jarvis coach           -> mode coach (lecture integrale)"
Write-Host "    jarvis telegram on     -> envoyer les vocaux sur Telegram"
Write-Host "    jarvis aide            -> liste des commandes"
Write-Host ""
