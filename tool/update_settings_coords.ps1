# Patches only the Settings document with the café coordinates, safely.
#
#   $env:HL_ADMIN_EMAIL='...'; $env:HL_ADMIN_PASSWORD='...'
#   powershell -ExecutionPolicy Bypass -File tool\update_settings_coords.ps1
#
# ## Why a separate script instead of re-running tool/seed_firestore.ps1
#
# The seed refuses when any order exists (real trading history must not be buried
# under mock data), and it rewrites every document anyway. This one-op ship is for
# the narrow case: the Phase 1 delivery-address feature added cafeLat/cafeLng to
# the Settings document, and the live document predates them. The app falls back
# to the bundled café pin when the fields are absent, so this keeps the live
# document in sync with the pin the owner confirmed and lets them see exactly
# what is stored.
#
# Values default to the bundled café pin (owner-confirmed). Override per run:
#   ... -CafeLat 14.3067497 -CafeLng 121.4773666
param(
  [double]$CafeLat = 14.3067497,
  [double]$CafeLng = 121.4773666,
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$gsp = Join-Path $repoRoot "android\app\google-services.json"
if (-not (Test-Path $gsp)) { throw "google-services.json not found at $gsp." }
$gspJson = Get-Content $gsp -Raw | ConvertFrom-Json
$projectId = $gspJson.project_info.project_id
$apiKey = $gspJson.client[0].api_key[0].current_key

$adminEmail = $env:HL_ADMIN_EMAIL
$adminPassword = $env:HL_ADMIN_PASSWORD
if (-not $adminEmail -or -not $adminPassword) {
  throw "Set the admin credentials with:`n  `$env:HL_ADMIN_EMAIL='...'`n  `$env:HL_ADMIN_PASSWORD='...'"
}

$body = @{ email = $adminEmail; password = $adminPassword; returnSecureToken = $true } | ConvertTo-Json
$token = (Invoke-RestMethod `
  -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
  -Method Post -Body $body -ContentType "application/json").idToken
$headers = @{ Authorization = "Bearer $token" }

$doc = "settings/highlanders"
$docUri = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/$doc"

Write-Host "project:  $projectId" -ForegroundColor DarkGray
Write-Host "document: $doc" -ForegroundColor DarkGray
Write-Host "coords:   $CafeLat, $CafeLng" -ForegroundColor DarkGray

$current = $null
try {
  $current = Invoke-RestMethod -Uri $docUri -Headers $headers -Method Get
} catch {
  $current = $null
}

if ($null -eq $current) {
  Write-Host "WARNING: settings/highlanders is not readable (missing or refused)." -ForegroundColor Yellow
} else {
  $f = $current.fields
  Write-Host ("current: cafeName={0} isOpen={1} cafeLat={2} cafeLng={3}" -f `
    $f.cafeName.stringValue, $f.isOpen.booleanValue, $f.cafeLat.doubleValue, $f.cafeLng.doubleValue) -ForegroundColor DarkGray
}

if ($Check) {
  Write-Host ""
  Write-Host "no document written (-Check). Values above are what a real run would set." -ForegroundColor Cyan
  exit 0
}

# The canonical single-document update is a PATCH with an updateMask naming just
# the two fields. (The `:commit` batch endpoint refused these writes with a bare
# 400 here, while PATCH is accepted — matching what a client SDK would send.)
$fields = @{
  fields = @{
    cafeLat = @{ doubleValue = $CafeLat }
    cafeLng = @{ doubleValue = $CafeLng }
  }
} | ConvertTo-Json -Depth 10

$docParams = "updateMask.fieldPaths=cafeLat&updateMask.fieldPaths=cafeLng"
Invoke-RestMethod -Uri "$docUri`?$docParams" -Headers $headers -Method Patch -Body $fields -ContentType "application/json" | Out-Null

# Verify by re-reading, so a rules refusal or a shape mismatch surfaces here
# rather than being discovered later from the admin panel.
$verify = Invoke-RestMethod -Uri $docUri -Headers $headers -Method Get
$vf = $verify.fields
Write-Host ""
Write-Host ("stored: cafeLat={0} cafeLng={1}" -f $vf.cafeLat.doubleValue, $vf.cafeLng.doubleValue) -ForegroundColor Green

if ($vf.cafeLat.doubleValue -ne $CafeLat -or $vf.cafeLng.doubleValue -ne $CafeLng) {
  throw "Read-back does not match the values that were written."
}
Write-Host "verified" -ForegroundColor Green