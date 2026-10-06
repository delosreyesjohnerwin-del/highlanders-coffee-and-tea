# Replaces the menu in Firestore (menuCategories + menuItems) with the café's
# real menu, without touching orders, promos, staff or settings.
#
#   $env:HL_ADMIN_EMAIL='...'; $env:HL_ADMIN_PASSWORD='...'
#   powershell -ExecutionPolicy Bypass -File tool\replace_menu.ps1
#   powershell -ExecutionPolicy Bypass -File tool\replace_menu.ps1 -Check
#
# ## Why this is not a second run of tool\seed_firestore.ps1
#
# Seeding refuses when any order exists (54 do), because it would bury real
# trading history under mock orders. The menu is different from history: menu
# documents are reference data the shop is expected to replace, and the old
# invented items must be removed or they keep showing in the customer app next
# to the real ones. So this script deletes every menuCategories/menuItems
# document and writes the new set in one atomic commit.
#
# ## Why the delete + write is safe against the old seeded items
#
# The old doc ids (m-kopi, m-americano, coffee, brews, ...) differ from the new
# ids (pz-hawaiian, cl-americano, pizza, ...), so the commit deletes the stale
# set and creates the new one with no overlapping writes. One id does overlap:
# the category 'noncoffee' survives the rename. It is therefore updated in
# place (an upsert) and never deleted, so no single document is both deleted and
# created in one batch.
#
# ## Source of truth
#
# The document shapes come from `tool/seed_documents.json`, which is generated
# by the app's own serialisers (tool/dump_seed_documents.dart). Hand-writing
# documents here would let the probe pass on shapes the app would never send.
param(
  [string]$ProjectId = "",
  [string]$Database = "(default)",
  [switch]$Check
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- configuration ------------------------------------------------------------

$gsp = Join-Path $repoRoot "android\app\google-services.json"
if (-not (Test-Path $gsp)) { throw "google-services.json not found at $gsp." }
$gspJson = Get-Content $gsp -Raw | ConvertFrom-Json
if (-not $ProjectId) { $ProjectId = $gspJson.project_info.project_id }
$apiKey = $gspJson.client[0].api_key[0].current_key

$docsPath = Join-Path $PSScriptRoot "seed_documents.json"
if (-not (Test-Path $docsPath)) {
  throw "seed_documents.json is missing. Run:`n  flutter test tool/dump_seed_documents.dart"
}

$docs = Get-Content $docsPath -Raw | ConvertFrom-Json
$newPaths = @($docs.PSObject.Properties.Name | Where-Object { $_ -like "menuItems/*" -or $_ -like "menuCategories/*" })
$newItems = @($newPaths | Where-Object { $_ -like "menuItems/*" })
$newCats = @($newPaths | Where-Object { $_ -like "menuCategories/*" })

Write-Host "project:    $ProjectId" -ForegroundColor DarkGray
Write-Host "database:   $Database" -ForegroundColor DarkGray
Write-Host "to write:   $($newCats.Count) categories, $($newItems.Count) menu items" -ForegroundColor DarkGray

# --- sign in ------------------------------------------------------------------

function SignIn([string]$email, [string]$password) {
  $body = @{ email = $email; password = $password; returnSecureToken = $true } | ConvertTo-Json
  return (Invoke-RestMethod `
    -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
    -Method Post -Body $body -ContentType "application/json").idToken
}

$adminEmail = $env:HL_ADMIN_EMAIL
$adminPassword = $env:HL_ADMIN_PASSWORD
if (-not $adminEmail -or -not $adminPassword) {
  throw "Set the admin credentials with:`n  `$env:HL_ADMIN_EMAIL='...'`n  `$env:HL_ADMIN_PASSWORD='...'"
}

$token = SignIn $adminEmail $adminPassword
$headers = @{ Authorization = "Bearer $token" }

function DocName([string]$path) {
  return "projects/$ProjectId/databases/$Database/documents/$path"
}

# --- list what is there -------------------------------------------------------
#
# List *all* documents in a collection, returning their full document names.
# Orders can be huge so this is deliberately scoped to the two menu collections
# only; the existing docs are what get deleted.

function List-Documents([string]$collection) {
  $query = @{
    structuredQuery = @{
      from = @(@{ collectionId = $collection })
      orderBy = @(@{ field = @{ fieldPath = "__name__" }; direction = "ASCENDING" })
    }
  } | ConvertTo-Json -Depth 10

  $result = Invoke-RestMethod `
    -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:runQuery" `
    -Headers $headers -Method Post -Body $query -ContentType "application/json"

  return @($result | Where-Object { $_.document } | ForEach-Object { $_.document.name })
}

function Count-Documents([string]$collection) {
  $query = @{ structuredQuery = @{ from = @(@{ collectionId = $collection }) } } | ConvertTo-Json -Depth 8
  $result = Invoke-RestMethod `
    -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:runQuery" `
    -Headers $headers -Method Post -Body $query -ContentType "application/json"
  return ($result | Measure-Object).Count
}

$existing = @(List-Documents "menuItems")
$existingCats = @(List-Documents "menuCategories")

Write-Host ""
Write-Host ("now in Firestore: {0} menu items, {1} categories" -f $existing.Count, $existingCats.Count) -ForegroundColor DarkGray

# --- typed values -------------------------------------------------------------

function ToFirestoreValue($value) {
  if ($null -eq $value) { return @{ nullValue = $null } }
  if ($value -is [bool]) { return @{ booleanValue = $value } }
  if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) {
    return @{ doubleValue = $value }
  }
  # String before IEnumerable: a PowerShell string *is* IEnumerable and would
  # otherwise be iterated into characters and recursed on forever.
  if ($value -is [string]) { return @{ stringValue = $value } }
  if ($value -is [PSCustomObject]) {
    $fields = @{}
    foreach ($p in $value.PSObject.Properties) { $fields[$p.Name] = ToFirestoreValue $p.Value }
    return @{ mapValue = @{ fields = $fields } }
  }
  if ($value -is [System.Collections.IDictionary]) {
    $fields = @{}
    foreach ($key in $value.Keys) { $fields[$key] = ToFirestoreValue $value[$key] }
    return @{ mapValue = @{ fields = $fields } }
  }
  if ($value -is [System.Collections.IEnumerable]) {
    return @{ arrayValue = @{ values = @($value | ForEach-Object { ToFirestoreValue $_ }) } }
  }
  return @{ stringValue = [string]$value }
}

# --- decide the writes --------------------------------------------------------

# Every new path becomes an upsert. It creates missing documents and replaces
# existing ones (the survival path for category 'noncoffee').
$deletes = @()
foreach ($docName in @($existing + $existingCats)) {
  # Only the part after .../documents/ is the path key form used in the JSON.
  $key = $docName -replace "^.*/documents/", ""
  if ($newPaths -notcontains $key) { $deletes += $key }
}

if ($Check) {
  Write-Host ""
  Write-Host "check mode - nothing written" -ForegroundColor Cyan
  Write-Host "  would delete: $($deletes.Count) stale document(s)"
  Write-Host "  would write:  $($newPaths.Count) document(s)"
  Write-Host ""
  Write-Host "  stale examples:" -ForegroundColor DarkGray
  ($deletes | Select-Object -First 5) | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
  if ($deletes.Count -gt 5) { Write-Host "    ..." -ForegroundColor DarkGray }
  exit 0
}

# --- write --------------------------------------------------------------------

Write-Host ""
Write-Host "writing..." -ForegroundColor Cyan

$writes = @()
foreach ($key in $deletes) {
  $writes += @{ delete = (DocName $key) }
}
foreach ($key in $newPaths) {
  $fields = @{}
  foreach ($p in $docs.$key.PSObject.Properties) {
    $fields[$p.Name] = ToFirestoreValue $p.Value
  }
  $writes += @{
    update = @{ name = (DocName $key); fields = $fields }
    updateMask = @{ fieldPaths = @($fields.Keys) }
  }
}

# One atomic commit, matching the app's WriteBatch: a refused document fails the
# whole thing rather than leaving the menu half old, half new.
$body = @{ writes = $writes } | ConvertTo-Json -Depth 20

Invoke-RestMethod `
  -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:commit" `
  -Headers $headers -Method Post -Body $body -ContentType "application/json" | Out-Null

Write-Host "  committed $($deletes.Count) delete(s) + $($newPaths.Count) write(s)" -ForegroundColor Green

# --- verify by reading back ---------------------------------------------------

Write-Host ""
Write-Host "reading back as a customer would" -ForegroundColor Cyan

$itemCount = Count-Documents "menuItems"
$catCount = Count-Documents "menuCategories"
Write-Host "  menuItems:      $itemCount"
Write-Host "  menuCategories: $catCount"

# Referential integrity: every item points at a category that exists. A menu
# with orphan items renders a wrong-looking shop, and silently so.
#
# The response must be assigned to a variable *before* it is filtered. Windows
# PowerShell 5.1's Invoke-RestMethod emits a top-level JSON array as one object
# rather than unrolling it, so filtering in the same pipeline sees a single
# array and the whole verification measures nothing. (This bit once: the count
# came back right because Measure-Object enumerates, but every doc looked
# "missing" and every orphan check compared against an array-shaped value.)
$itemResp = Invoke-RestMethod `
  -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:runQuery" `
  -Headers $headers -Method Post `
  -Body (@{ structuredQuery = @{ from = @(@{ collectionId = "menuItems" }) } } | ConvertTo-Json -Depth 8) `
  -ContentType "application/json"
$itemDocs = @($itemResp | Where-Object { $_.document })

$catResp = Invoke-RestMethod `
  -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:runQuery" `
  -Headers $headers -Method Post `
  -Body (@{ structuredQuery = @{ from = @(@{ collectionId = "menuCategories" }) } } | ConvertTo-Json -Depth 8) `
  -ContentType "application/json"
$catDocs = @($catResp | Where-Object { $_.document })

$catIds = @($catDocs | ForEach-Object { $_.document.fields.id.stringValue })
$orphans = @($itemDocs | Where-Object { $catIds -notcontains $_.document.fields.categoryId.stringValue })
Write-Host ("  referential integrity: {0} orphans" -f $orphans.Count)
foreach ($o in $orphans) {
  Write-Host ("    WARNING: {0} -> category '{1}' missing" -f `
    $o.document.name.Split('/')[-1], $o.document.fields.categoryId.stringValue)
}

# Spot-check the prices that must be exactly right: the owner's numbers, and a
# drink priced from its hot column.
function Find-Item([string]$id) {
  return $itemDocs | Where-Object { $_.document.name.Split('/')[-1] -eq $id } | Select-Object -First 1
}

function Check-Price([string]$id, [double]$expected) {
  $doc = Find-Item $id
  if ($null -eq $doc) { Write-Host "  FAIL: $id missing" -ForegroundColor Red; return $false }
  $got = $doc.document.fields.price.doubleValue
  $ok = $got -eq $expected
  $mark = if ($ok) { "ok " } else { "FAIL" }
  $color = if ($ok) { "Green" } else { "Red" }
  Write-Host ("  {0}  {1,-20} price {2} (expect {3})" -f $mark, $id, $got, $expected) -ForegroundColor $color
  return $ok
}

$allOk = $true
$allOk = $allOk -and (Check-Price "pz-hawaiian" 349)
$allOk = $allOk -and (Check-Price "pz-overload" 449)
$allOk = $allOk -and (Check-Price "cl-americano" 129)
$allOk = $allOk -and (Check-Price "cl-dirty-matcha" 189)
$allOk = $allOk -and (Check-Price "fr-ube-macapuno" 179)
$allOk = $allOk -and (Check-Price "bf-hickory-ribs" 469)

Write-Host ""
if ($itemCount -ne $newItems.Count -or $catCount -ne $newCats.Count -or $orphans.Count -gt 0 -or -not $allOk) {
  Write-Host "REPLACE FAILED VERIFICATION" -ForegroundColor Red
  exit 1
}

Write-Host "menu replaced and verified" -ForegroundColor Green
Write-Host ""
Write-Host "The menu is now $itemCount items / $catCount categories. Old invented" -ForegroundColor DarkGray
Write-Host "items are gone. Order history still shows the old snapshot names, which" -ForegroundColor DarkGray
Write-Host "is correct: those are historical orders, not live menu entries." -ForegroundColor DarkGray
exit 0