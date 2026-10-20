<#
.SYNOPSIS
  Seeds the parking lots and slots into the running emulators (resets slot states).

.PARAMETER Project
  Same project ID the emulators were started with.
#>
param(
  [string]$Project = 'sps-app-dev'
)

$ErrorActionPreference = 'Stop'
$uri = "http://127.0.0.1:5001/$Project/us-central1/migrateLots"
# migrateLots is admin-only; the emulator treats unauthenticated calls as admin
$response = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body '{"data":{}}' -TimeoutSec 120
Write-Host ("Seeded {0} lots and {1} slots in {2}" -f $response.result.migratedLots, $response.result.migratedSlots, $Project)
