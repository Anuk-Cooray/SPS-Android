<#
.SYNOPSIS
  Runs the dev flavor of the app against the local Firebase emulators.

.DESCRIPTION
  Start the emulators first (.\scripts\start-emulators.ps1). On the Android emulator the app
  reaches them through 10.0.2.2 automatically.

.PARAMETER Device
  Flutter device ID (see `flutter devices`), e.g. emulator-5554. Omit to let Flutter choose.

.PARAMETER ToolsDir
  Folder holding jdk-21\ (used for the Android build).

.PARAMETER EmulatorHost
  Address of the PC running the emulators. Leave unset for the Android emulator; for a real
  phone or tablet use the PC's Wi-Fi address and start the emulators with -Lan.
#>
param(
  [string]$Device,
  [string]$ToolsDir = (Join-Path $env:USERPROFILE 'tools'),
  [string]$EmulatorHost
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$jdk = Join-Path $ToolsDir 'jdk-21'
if (Test-Path (Join-Path $jdk 'bin\java.exe')) { $env:JAVA_HOME = $jdk }

# Windows: the JVM's Unix-socket temp path must be short or Gradle fails to start
$socketDir = 'C:\Users\Public\sps-emu'
New-Item -ItemType Directory -Force -Path $socketDir | Out-Null
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$socketDir"

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = Join-Path $env:USERPROFILE 'flutter_sdk\bin\flutter.bat' }
if (-not (Test-Path $flutter)) { throw 'Flutter SDK not found; add flutter to PATH.' }
# Native-asset build hooks break on paths with spaces; use the 8.3 short path when available
try {
  $flutter = (New-Object -ComObject Scripting.FileSystemObject).GetFile($flutter).ShortPath
} catch {}

$runArgs = @('run', '--flavor', 'dev', '--dart-define=USE_EMULATORS=true', '--dart-define=ENVIRONMENT=dev')
if ($EmulatorHost) { $runArgs += "--dart-define=EMULATOR_HOST=$EmulatorHost" }
if ($Device) { $runArgs += @('-d', $Device) }

Push-Location $root
try {
  & $flutter @runArgs
} finally {
  Pop-Location
}
