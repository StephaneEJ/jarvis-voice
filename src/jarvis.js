// jarvis.js — Plugin vocal Jarvis pour OpenCode
// Compatible Linux, Mac, Windows
// Contrôle via ~/.claude/jarvis.conf (Linux/Mac) ou %USERPROFILE%\.claude\jarvis.conf (Windows)

import { readFileSync, writeFileSync, existsSync, unlinkSync, appendFileSync } from "fs"
import { tmpdir, homedir, platform } from "os"
import { join } from "path"
import { spawn, spawnSync } from "child_process"

const HOME = homedir()
const OS   = platform() // 'linux' | 'darwin' | 'win32'

// Trouver Python sur Windows (WinPython portable, puis PATH sans le stub WindowsApps)
function findPython() {
  if (OS !== "win32") return null
  const candidates = [
    join(HOME, "WinPython", "WPy64-312101", "python", "python.exe"),
    join(HOME, "WinPython", "python", "python.exe"),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  try {
    const r = spawnSync("where", ["python"], { timeout: 5000, encoding: "utf8" })
    if (r.status === 0) {
      const lines = r.stdout.trim().split(/\r?\n/)
      for (const line of lines) {
        if (!line.includes("WindowsApps")) return line.trim()
      }
    }
  } catch {}
  return null
}

const WIN_PYTHON = findPython()

// ============================================================
// FILE D'ATTENTE AUDIO — empêche la superposition de lectures
// ============================================================
const audioQueue = []
let audioPlaying = false
let currentPlayer = null
let currentTts = null
const STOP_SIGNAL = join(tmpdir(), "jarvis-stop")

function shouldStop() {
  if (existsSync(STOP_SIGNAL)) {
    try { unlinkSync(STOP_SIGNAL) } catch {}
    return true
  }
  return false
}

function killAudio() {
  audioQueue.length = 0
  if (currentTts && !currentTts.killed) {
    try { currentTts.kill("SIGTERM") } catch {}
    currentTts = null
  }
  if (currentPlayer && !currentPlayer.killed) {
    try { currentPlayer.kill("SIGTERM") } catch {}
    currentPlayer = null
  }
  audioPlaying = false
}

function enqueueAudio(text, voice, rate) {
  if (!text) return
  audioQueue.push({ text, voice, rate })
  processQueue()
}

function processQueue() {
  if (audioPlaying || audioQueue.length === 0) return
  if (shouldStop()) { killAudio(); return }
  audioPlaying = true
  const { text, voice, rate } = audioQueue.shift()
  playEdgeTts(text, voice, rate, () => {
    currentPlayer = null
    currentTts = null
    audioPlaying = false
    processQueue()
  })
}

// ============================================================
// LECTURE AUDIO — cross-platform
// ============================================================
function playFileAsync(filePath, onDone) {
  let player
  if (OS === "darwin") {
    player = spawn("afplay", [filePath])
  } else if (OS === "win32") {
    // VBScript wrapper + Dispatcher WPF pour lecture MP3 sans flash fenêtre
    const resolved = filePath.replace(/\\/g, "\\\\").replace(/'/g, "''")
    const playPs1 = join(tmpdir(), `jarvis_play_${Date.now()}.ps1`)
    const vbsFile = join(tmpdir(), `jarvis_launch_${Date.now()}.vbs`)
    const psScript = `
Add-Type -AssemblyName presentationCore
$player = New-Object System.Windows.Media.MediaPlayer
$player.Open([uri]::new('${filePath.replace(/\\/g, "/")}'))
Start-Sleep -Milliseconds 300
$player.Play()
$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$tick = 0
$timer.Add_Tick({
    $script:tick++
    if ($player.NaturalDuration.HasTimeSpan -and $player.Position -ge $player.NaturalDuration.TimeSpan) {
        $player.Close()
        $dispatcher.InvokeShutdown()
    }
    if ($script:tick -gt 150) { $dispatcher.InvokeShutdown() }
})
$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
Remove-Item '${filePath.replace(/'/g, "''")}' -Force -ErrorAction SilentlyContinue
Remove-Item '${playPs1.replace(/'/g, "''")}' -Force -ErrorAction SilentlyContinue
`
    const vbsScript = `Set shell = CreateObject("WScript.Shell")\r\nshell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""${playPs1}""", 0, True\r\nCreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName\r\n`
    try { writeFileSync(playPs1, psScript, "utf8") } catch {}
    try { writeFileSync(vbsFile, vbsScript, "ascii") } catch {}
    player = spawn("wscript.exe", [vbsFile])
  } else {
    player = spawn("paplay", [filePath])
    player.on("error", () => {
      currentPlayer = spawn("aplay", ["-q", filePath])
      currentPlayer.on("close", () => { try { unlinkSync(filePath) } catch {}; onDone() })
      currentPlayer.on("error", () => { try { unlinkSync(filePath) } catch {}; onDone() })
    })
  }
  currentPlayer = player
  player.on("close", () => { currentPlayer = null; try { unlinkSync(filePath) } catch {}; onDone() })
  player.on("error", () => { currentPlayer = null; try { unlinkSync(filePath) } catch {}; onDone() })
}

function playFileSync(filePath) {
  if (OS === "darwin") {
    spawnSync("afplay", [filePath], { timeout: 60000 })
  } else if (OS === "win32") {
    // VBScript wrapper + Dispatcher WPF pour lecture MP3 sans flash fenêtre
    const playPs1 = join(tmpdir(), `jarvis_play_sync_${Date.now()}.ps1`)
    const vbsFile = join(tmpdir(), `jarvis_launch_sync_${Date.now()}.vbs`)
    const psScript = `
Add-Type -AssemblyName presentationCore
$player = New-Object System.Windows.Media.MediaPlayer
$player.Open([uri]::new('${filePath.replace(/\\/g, "/")}'))
Start-Sleep -Milliseconds 300
$player.Play()
$dispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(200)
$tick = 0
$timer.Add_Tick({
    $script:tick++
    if ($player.NaturalDuration.HasTimeSpan -and $player.Position -ge $player.NaturalDuration.TimeSpan) {
        $player.Close()
        $dispatcher.InvokeShutdown()
    }
    if ($script:tick -gt 150) { $dispatcher.InvokeShutdown() }
})
$timer.Start()
[System.Windows.Threading.Dispatcher]::Run()
Remove-Item '${playPs1.replace(/'/g, "''")}' -Force -ErrorAction SilentlyContinue
`
    const vbsScript = `Set shell = CreateObject("WScript.Shell")\r\nshell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""${playPs1}""", 0, True\r\nCreateObject("Scripting.FileSystemObject").DeleteFile WScript.ScriptFullName\r\n`
    try { writeFileSync(playPs1, psScript, "utf8") } catch {}
    try { writeFileSync(vbsFile, vbsScript, "ascii") } catch {}
    spawnSync("wscript.exe", [vbsFile], { timeout: 30000 })
  } else {
    const r = spawnSync("paplay", [filePath], { timeout: 60000 })
    if (r.status !== 0) spawnSync("aplay", ["-q", filePath], { timeout: 60000 })
  }
}

function playEdgeTts(text, voice, rate, onDone) {
  const tmp = join(tmpdir(), `jarvis_${Date.now()}.mp3`)
  const ttsArgs = ["--voice", voice, "--text", text, "--write-media", tmp]
  if (rate) ttsArgs.push("--rate", rate)

  let edgeTts
  if (OS === "win32" && WIN_PYTHON) {
    edgeTts = spawn(WIN_PYTHON, ["-m", "edge_tts", ...ttsArgs])
  } else {
    edgeTts = spawn("edge-tts", ttsArgs)
  }
  currentTts = edgeTts

  edgeTts.on("close", (code) => {
    currentTts = null
    if (shouldStop()) { killAudio(); try { unlinkSync(tmp) } catch {}; onDone(); return }
    if (code === 0 && existsSync(tmp)) {
      playFileAsync(tmp, onDone)
    } else {
      speakFallback(text)
      onDone()
    }
  })

  edgeTts.on("error", () => {
    currentTts = null
    speakFallback(text)
    onDone()
  })
}

// ============================================================
// CONFIG
// ============================================================
function getConfPath() {
  if (OS === "win32") {
    return join(process.env.USERPROFILE || HOME, ".claude", "jarvis.conf")
  }
  return join(HOME, ".claude", "jarvis.conf")
}

function loadConfig() {
  const conf = {
    JARVIS_ENABLED: "true",
    JARVIS_MODE: "court",
    JARVIS_VOICE: "fr-FR-HenriNeural",
    JARVIS_TRANSCRIPT: "false",
    JARVIS_RATE: "+25%",
  }
  try {
    const confPath = getConfPath()
    if (existsSync(confPath)) {
      for (const line of readFileSync(confPath, "utf8").split("\n")) {
        const t = line.trim()
        if (!t || t.startsWith("#")) continue
        const idx = t.indexOf("=")
        if (idx > 0) {
          const k = t.slice(0, idx).trim()
          const v = t.slice(idx + 1).trim()
          if (k && v) conf[k] = v
        }
      }
    }
  } catch {}
  return conf
}

// ============================================================
// FALLBACKS (synchrones, textes courts)
// ============================================================
function speakFallback(text) {
  if (OS === "darwin") {
    spawnSync("say", ["-v", "Thomas", text], { timeout: 15000 })
  } else if (OS === "win32") {
    const script = `
      Add-Type -AssemblyName System.Speech
      $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
      try { $s.SelectVoiceByHints('Female', 'Adult', 0, [System.Globalization.CultureInfo]::new('fr-FR')) } catch {}
      $s.Speak('${text.replace(/'/g, "''")}')
    `
    spawnSync("powershell", ["-NoProfile", "-Command", script], { timeout: 15000 })
  } else {
    // Linux : Piper puis espeak-ng
    const piperBin   = join(HOME, "piper", "piper", "piper")
    const piperModel = join(HOME, "piper", "models", "fr_FR-tom-medium.onnx")
    if (existsSync(piperBin) && existsSync(piperModel)) {
      const wavTmp = join(tmpdir(), `jarvis_${Date.now()}.wav`)
      const gen = spawnSync(piperBin, ["--model", piperModel, "--output_file", wavTmp], {
        input: text, encoding: "utf8", timeout: 15000,
      })
      if (gen.status === 0 && existsSync(wavTmp)) {
        spawnSync("paplay", [wavTmp], { timeout: 60000 })
        try { unlinkSync(wavTmp) } catch {}
        return
      }
    }
    spawnSync("espeak-ng", ["-v", "fr", "-s160", text], { timeout: 30000 })
  }
}

// Lecture vocale synchrone (pour messages courts : erreurs, permissions)
function speakSync(text, voice, rate) {
  if (!text) return

  const tmp = join(tmpdir(), `jarvis_${Date.now()}.mp3`)
  const ttsArgs = ["--voice", voice, "--text", text, "--write-media", tmp]
  if (rate) ttsArgs.push("--rate", rate)

  let edgeTts
  if (OS === "win32" && WIN_PYTHON) {
    edgeTts = spawnSync(WIN_PYTHON, ["-m", "edge_tts", ...ttsArgs], { timeout: 30000 })
  } else {
    edgeTts = spawnSync("edge-tts", ttsArgs, { timeout: 30000 })
  }
  if (edgeTts.status === 0 && existsSync(tmp)) {
    playFileSync(tmp)
    try { unlinkSync(tmp) } catch {}
    return
  }

  speakFallback(text)
}

// ============================================================
// NETTOYAGE MARKDOWN -> TEXTE ORAL
// ============================================================
function cleanForSpeech(text) {
  if (!text) return ""
  return text
    .replace(/```[\s\S]*?```/g, "")
    .replace(/`[^`]+`/g, "")
    .replace(/#{1,6}\s+/g, "")
    .replace(/\*\*/g, "")
    .replace(/\*/g, "")
    .replace(/\|[^\n]+\|/g, "")
    .replace(/^[-*]\s+/gm, "")
    .replace(/^\d+\.\s+/gm, "")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/\[\[([^\]]+)\]\]/g, "$1")
    .replace(/^>\s+/gm, "")
    .replace(/---+/g, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}

// ============================================================
// EXTRACTION DE RÉSUMÉ (mode court / detail / coach)
// ============================================================
function extractSummary(text, mode) {
  const clean = cleanForSpeech(text)
  if (!clean) return null

  const flat = clean.replace(/\n+/g, " ").trim()
  const sentences = flat.match(/[^.!?]+[.!?]+/g) || []

  if (mode === "coach") {
    return flat || null
  }

  let maxLen
  switch (mode) {
    case "detail": maxLen = 600; break
    default:       maxLen = 250; break
  }

  let summary = ""
  for (const s of sentences) {
    if ((summary + s).length > maxLen) break
    summary += s.trim() + " "
  }
  return summary.trim() || flat.slice(0, maxLen)
}

// ============================================================
// TRANSCRIPT
// ============================================================
function logTranscript(role, text) {
  const logPath = join(tmpdir(), "jarvis-coach-transcript.jsonl")
  const entry = {
    timestamp: new Date().toISOString(),
    role,
    text: text.slice(0, 5000),
  }
  try {
    appendFileSync(logPath, JSON.stringify(entry) + "\n", "utf8")
  } catch {}
}

const ERROR_PATTERNS = /traceback|error:|exception|erreur|fatal|failed|command not found|permission denied|no such file/i

// Suivi de session
let lastAssistantText = ""
let hasErrors = false

function reset() {
  lastAssistantText = ""
  hasErrors = false
}

// ============================================================
// PLUGIN PRINCIPAL
// ============================================================
export const JarvisPlugin = async ({ $ }) => {
  return {
    event: async ({ event }) => {
      const conf = loadConfig()
      if (conf.JARVIS_ENABLED !== "true") return
      const voice = conf.JARVIS_VOICE || "fr-FR-HenriNeural"
      const mode = conf.JARVIS_MODE || "court"
      const transcriptEnabled = conf.JARVIS_TRANSCRIPT === "true"
      const rate = conf.JARVIS_RATE || "+25%"

      if (event.type === "message.part.updated") {
        const part = event.properties?.part || {}

        // Capture le texte de la réponse IA
        if (part.type === "text" && part.text) {
          lastAssistantText = part.text
        }

        // Détection d'erreur sur les outils
        if (part.type === "tool") {
          const status = part.state?.status
          if (status !== "completed" && status !== "error") return
          const tool      = part.tool || ""
          const outputStr = typeof part.state?.output === "string" ? part.state.output : ""
          const errorStr  = typeof part.state?.error  === "string" ? part.state.error  : ""
          const isError   = status === "error"
            || errorStr.length > 0
            || (tool === "bash" && ERROR_PATTERNS.test(outputStr))
          if (isError && !hasErrors) {
            hasErrors = true
            speakSync("Attention, une erreur a été détectée.", voice, rate)
          }
        }
      }

      // Demande de confirmation
      else if (event.type === "permission.asked") {
        speakSync("j'ai besoin de toi", voice, rate)
      }

      // Fin de réponse — utilise la queue audio
      else if (event.type === "session.idle") {
        if (shouldStop()) { killAudio() }
        if (!lastAssistantText) { reset(); return }

        const summary = extractSummary(lastAssistantText, mode)
        if (summary) enqueueAudio(summary, voice, rate)

        // Transcript si activé
        if (transcriptEnabled && lastAssistantText) {
          logTranscript("assistant", lastAssistantText)
        }

        reset()
      }
    },
  }
}
