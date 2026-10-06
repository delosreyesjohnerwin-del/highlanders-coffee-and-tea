# Runs every Firestore query the app issues, against the live project, and fails
# if any of them cannot execute.
#
#   $env:HL_ADMIN_EMAIL    = '...'
#   $env:HL_ADMIN_PASSWORD = '...'
#   powershell -ExecutionPolicy Bypass -File tool\verify_queries.ps1
#
# ## Why this exists
#
# The unit tests use MemoryShopRepository. They are thorough and they are also
# incapable of catching the entire class of failure this tool covers, because an
# in-memory list has no query planner, no rules and no indexes. Every test can be
# green while the shipped app cannot read its own data.
#
# That is not hypothetical. The order-history query combined an equality filter
# with a sort:
#
#     .where('customerUid', isEqualTo: uid)
#     .orderBy('createdAt', descending: true)
#
# Firestore answers FAILED_PRECONDITION -- "The query requires an index" -- for
# that shape without a composite index, and this project declared none. The
# sign-in succeeded, the admin panel rendered, the dashboard numbers were correct,
# and underneath it the customer's order history was permanently empty. Nothing
# failed loudly; there was just no data, forever, on a screen designed to show it.
#
# A test would not have found it. Running the actual query does, in one second.
#
# ## The coverage check
#
# The registry below is transcribed from the Dart, which means it can drift -- the
# same trap as a hand-written script that disagrees with the code it checks. So
# before running anything, the counts of `.where(` and `.orderBy(` in the source
# are compared against how many are registered here. Add a query and forget this
# file, and the tool fails and says so rather than passing on a stale list.
param([switch]$SkipLive)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$repoSrc = Join-Path $repoRoot "lib\data\firestore\firestore_shop_repository.dart"

# --- coverage ------------------------------------------------------------------

$src = Get-Content $repoSrc -Raw
$srcWhere = ([regex]::Matches($src, '\.where\(')).Count
$srcOrderBy = ([regex]::Matches($src, '\.orderBy\(')).Count
$srcLimit = ([regex]::Matches($src, '\.limit\(')).Count

# Query shapes as the app issues them. `RequiresOrdering` marks the ones that are
# only correct with a server-side sort -- today that is none of them, because
# every ordering in this repository is re-done client-side from parsed createdAt
# or sortOrder. The flag exists so a future `.limit()` is impossible to add
# without stating that the query now needs an index.
$queries = @(
  @{ Name = 'menu items by sortOrder';   Collection = 'menuItems';    Where = $null;      OrderBy = 'sortOrder';  Limit = $null }
  @{ Name = 'categories by sortOrder';   Collection = 'menuCategories'; Where = $null;    OrderBy = 'sortOrder';  Limit = $null }
  @{ Name = 'all orders, admin queue';   Collection = 'orders';       Where = $null;      OrderBy = 'createdAt';  Limit = $null }
  @{ Name = 'order history, live';       Collection = 'orders';       Where = 'customerUid'; OrderBy = $null;      Limit = $null }
  @{ Name = 'order history, one-shot';   Collection = 'orders';       Where = 'customerUid'; OrderBy = $null;      Limit = $null }
  @{ Name = 'addresses, one-shot';       Collection = 'addresses';    Where = 'uid';       OrderBy = $null;      Limit = $null }
  @{ Name = 'addresses, live';           Collection = 'addresses';    Where = 'uid';       OrderBy = $null;      Limit = $null }
  @{ Name = 'any order placed at all';   Collection = 'orders';       Where = $null;      OrderBy = $null;       Limit = 1 }
  @{ Name = 'staff roster';              Collection = 'staffMembers'; Where = $null;      OrderBy = $null;       Limit = $null }
  @{ Name = 'promotions';                Collection = 'promos';       Where = $null;      OrderBy = $null;       Limit = $null }
)

$regWhere = @($queries | Where-Object { $_.Where }).Count
$regOrderBy = @($queries | Where-Object { $_.OrderBy }).Count
$regLimit = @($queries | Where-Object { $_.Limit }).Count

Write-Host "coverage" -ForegroundColor Cyan
$coverageOk = $true
foreach ($p in @(
    @{ Label = '.where(';   S = $srcWhere;   R = $regWhere },
    @{ Label = '.orderBy('; S = $srcOrderBy; R = $regOrderBy },
    @{ Label = '.limit(';   S = $srcLimit;   R = $regLimit })) {
  if ($p.S -ne $p.R) {
    Write-Host ("  FAIL  {0} - {1} in the repository, {2} registered here" -f $p.Label, $p.S, $p.R) -ForegroundColor Red
    $coverageOk = $false
  } else {
    Write-Host ("  ok    {0} - {1} in the repository, {1} registered" -f $p.Label, $p.S) -ForegroundColor DarkGray
  }
}
if (-not $coverageOk) {
  Write-Host ""
  Write-Host "the registry in this file has drifted from the Dart source" -ForegroundColor Red
  Write-Host "update $repoSrc and the registry together" -ForegroundColor Red
  exit 1
}

if ($SkipLive) {
  Write-Host ""
  Write-Host "coverage checked only (-SkipLive); no query was executed" -ForegroundColor Yellow
  exit 0
}

# --- live ----------------------------------------------------------------------

$gsp = Join-Path $repoRoot "android\app\google-services.json"
if (-not (Test-Path $gsp)) { throw "google-services.json not found at $gsp. Cannot authenticate." }
$gspJson = Get-Content $gsp -Raw | ConvertFrom-Json
$proj = $gspJson.project_info.project_id
$apiKey = $gspJson.client[0].api_key[0].current_key

if (-not $env:HL_ADMIN_EMAIL -or -not $env:HL_ADMIN_PASSWORD) {
  throw "Set `$env:HL_ADMIN_EMAIL and `$env:HL_ADMIN_PASSWORD first."
}

$auth = Invoke-RestMethod -Method Post `
  -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
  -ContentType "application/json" `
  -Body (@{ email = $env:HL_ADMIN_EMAIL; password = $env:HL_ADMIN_PASSWORD; returnSecureToken = $true } | ConvertTo-Json)
$h = @{ Authorization = "Bearer $($auth.idToken)" }
$uri = "https://firestore.googleapis.com/v1/projects/$proj/databases/(default)/documents:runQuery"

Write-Host ""
Write-Host "live queries against $proj" -ForegroundColor Cyan
Write-Host "  signed in as $($auth.email)" -ForegroundColor DarkGray

$failures = 0
foreach ($q in $queries) {
  $structured = @{ from = @{ collectionId = $q.Collection } }
  if ($q.Where) {
    $structured.where = @{
      fieldFilter = @{
        field = @{ fieldPath = $q.Where }
        op    = "EQUAL"
        value = @{ stringValue = $auth.localId }
      }
    }
  }
  if ($q.OrderBy) {
    $structured.orderBy = @(@{ field = @{ fieldPath = $q.OrderBy }; direction = "DESCENDING" })
  }
  if ($q.Limit) { $structured.limit = $q.Limit }

  $body = @{ structuredQuery = $structured } | ConvertTo-Json -Depth 12
  $label = "{0}  [{1}]" -f $q.Name, $q.Collection

  try {
    $r = Invoke-RestMethod -Method Post -Uri $uri -Headers $h `
      -ContentType "application/json" -Body $body
    $err = @($r | Where-Object { $_.error }) | Select-Object -First 1
    if ($err) {
      Write-Host ("  FAIL  {0,-34} {1}" -f $label, $err.error.message) -ForegroundColor Red
      $failures++
    } else {
      $docs = @($r | Where-Object { $_.document }).Count
      Write-Host ("  ok    {0,-34} {1} doc(s)" -f $label, $docs) -ForegroundColor DarkGray
    }
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $msg = $sr.ReadToEnd()
      Write-Host ("  FAIL  {0,-34} HTTP {1} {2}" -f $label, [int]$resp.StatusCode, $msg) -ForegroundColor Red
    } else {
      Write-Host ("  FAIL  {0,-34} {1}" -f $label, $_.Exception.Message) -ForegroundColor Red
    }
    $failures++
  }
}

Write-Host ""
if ($failures -eq 0) {
  Write-Host "all $($queries.Count) queries executed" -ForegroundColor Green
  exit 0
}
Write-Host "$failures of $($queries.Count) queries FAILED" -ForegroundColor Red
Write-Host "a query that cannot run is a screen that shows nothing while every test stays green." -ForegroundColor Red
exit 1
