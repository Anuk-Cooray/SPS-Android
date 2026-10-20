<#
.SYNOPSIS
  Starts the Firebase emulators (Auth, Firestore, Functions) for free local development.

.DESCRIPTION
  Builds the Cloud Functions, then runs the emulators until you press Ctrl+C. Emulator data
  (users, bookings, lots) is saved to .\emulator-data on exit and loaded on the next start.
  On a fresh start, seed the parking lots once with .\scripts\seed-emulators.ps1.

.PARAMETER Project
  Project ID of the app flavor you run: dev -> sps-app-dev, prod -> sps-app-c3f90.

.PARAMETER ToolsDir
  Folder holding jdk-21\ and firebase.exe. Falls back to java/firebase on PATH.

.PARAMETER Fresh
  Ignore the saved emulator data and start empty.
#>
param(
  [string]$Project = 'sps-app-dev',
  [string]$ToolsDir = (Join-Path $env:USERPROFILE 'tools'),
  [switch]$Fresh
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$functionsDir = Join-Path $root 'functions'

$firebase = Join-Path $ToolsDir 'firebase.exe'
if (-not (Test-Path $firebase)) { $firebase = 'firebase' }

$jdk = Join-Path $ToolsDir 'jdk-21'
if (Test-Path (Join-Path $jdk 'bin\java.exe')) {
  $env:JAVA_HOME = $jdk
  $env:Path = (Join-Path $jdk 'bin') + ';' + $env:Path
}

# Windows: the JVM's Unix-socket temp path must be short or the Firestore emulator exits
$socketDir = 'C:\Users\Public\sps-emu'
New-Item -ItemType Directory -Force -Path $socketDir | Out-Null
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$socketDir"
# Functions load slowly from OneDrive; the default discovery timeout is too short
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'

# The functions declare HMAC_SECRET_KEY as a secret; the emulator reads it from .secret.local
$secretFile = Join-Path $functionsDir '.secret.local'
if (-not (Test-Path $secretFile)) {
  $envFile = Join-Path $functionsDir '.env'
  if (-not (Test-Path $envFile)) { $envFile = Join-Path $functionsDir '.env.example' }
  $line = Get-Content $envFile | Where-Object { $_ -match '^HMAC_SECRET_KEY=' } | Select-Object -First 1
  if (-not $line) { throw "HMAC_SECRET_KEY not found in $envFile" }
  Set-Content -Path $secretFile -Encoding ascii -Value @('# Local-only secrets for the Functions emulator (never commit)', $line)
  Write-Host "Created functions\.secret.local"
}

Push-Location $functionsDir
try {
  if (-not (Test-Path 'node_modules')) { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' } }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw 'Functions build failed' }
  # Load the module once so its files are cached; a cold load from OneDrive outlasts the
  # emulator's function discovery and fails with "fetch failed"
  node -e "require('./lib/index.js'); process.exit(0)" | Out-Null
} finally {
  Pop-Location
}

# Watchdog: if discovery still fails, touch lib\index.js so the emulator reloads (up to 3 times)
$debugLog = Join-Path $root 'firebase-debug.log'
Remove-Item $debugLog -ErrorAction SilentlyContinue
$watchdog = Start-Job -ArgumentList (Join-Path $functionsDir 'lib\index.js'), $debugLog -ScriptBlock {
  param($indexJs, $debugLog)
  $retries = 0
  for ($i = 0; $i -lt 100 -and $retries -lt 3; $i++) {
    Start-Sleep -Seconds 3
    if (-not (Test-Path $debugLog)) { continue }
    $text = Get-Content $debugLog -Raw
    if ($text -match 'Loaded functions definitions') { return }
    $failures = ([regex]::Matches($text, 'Failed to load function definition')).Count
    if ($failures -gt $retries) {
      $retries = $failures
      (Get-Item $indexJs).LastWriteTime = Get-Date
    }
  }
}

$dataDir = Join-Path $root 'emulator-data'
$fbArgs = @('emulators:start', '--only', 'auth,firestore,functions', '--project', $Project, '--export-on-exit', $dataDir)
if (-not $Fresh -and (Test-Path $dataDir)) {
  $fbArgs += @('--import', $dataDir)
} else {
  Write-Host "No saved data: once the emulators are ready, run .\scripts\seed-emulators.ps1 -Project $Project"
}

Push-Location $root
try {
  & $firebase @fbArgs
} finally {
  Stop-Job $watchdog -ErrorAction SilentlyContinue
  Remove-Job $watchdog -Force -ErrorAction SilentlyContinue
  Pop-Location
}
