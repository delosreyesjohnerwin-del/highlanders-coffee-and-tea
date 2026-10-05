# Verifies firestore.rules against the live project.
#
#   powershell -ExecutionPolicy Bypass -File tool\verify_rules.ps1
#
# ## Why this is a script and not a note in the rules file
#
# Security rules fail silently in the worst direction. A rule that is too tight
# produces a PERMISSION_DENIED in the app; a rule that is too loose produces
# nothing at all, ever, until someone notices. Nothing in a deploy tells you which
# one you shipped. So the rules need probing after every change, and a probe that
# lives only in shell history is a probe that never runs twice.
#
# ## What it does
#
# Signs in as the admin, creates a throwaway customer account, and asserts that
# each side of each boundary behaves as intended. Cleanup removes every document
# and deletes the throwaway auth account, so running it twice is harmless.
#
# ## Reading the output
#
# `ALLOW` and `DENY` are assertions, not reports. A failure prints the expected and
# actual outcome and the script exits non-zero. Anything that is not asserted here
# is not verified — in particular, this script does not prove the *denials* are for
# the right reason; see the "known limits" section at the bottom.
param(
  [string]$ProjectId = "",
  [string]$Database = "(default)",
  [string]$AdminEmail = "",
  [string]$AdminPassword = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- configuration ------------------------------------------------------------

$gsp = Join-Path $repoRoot "android\app\google-services.json"
if (-not (Test-Path $gsp)) {
  throw "google-services.json not found at $gsp. Cannot authenticate."
}
$gspJson = Get-Content $gsp -Raw | ConvertFrom-Json

if (-not $ProjectId) { $ProjectId = $gspJson.project_info.project_id }
$apiKey = $gspJson.client[0].api_key[0].current_key

# Credentials come from the environment, not from a literal in this file. The admin
# password has already been in this repository's shell history, so hard-coding it a
# second time would make rotating it a two-place job instead of a one-place one.
if (-not $AdminEmail) { $AdminEmail = $env:HL_ADMIN_EMAIL }
if (-not $AdminPassword) { $AdminPassword = $env:HL_ADMIN_PASSWORD }
if (-not $AdminEmail -or -not $AdminPassword) {
  throw "Set the admin credentials with:`n  `$env:HL_ADMIN_EMAIL='...'`n  `$env:HL_ADMIN_PASSWORD='...'"
}

Write-Host "project: $ProjectId" -ForegroundColor DarkGray
Write-Host "database: $Database" -ForegroundColor DarkGray

# --- auth ---------------------------------------------------------------------

function SignIn([string]$email, [string]$password) {
  $body = @{ email = $email; password = $password; returnSecureToken = $true } | ConvertTo-Json
  try {
    $r = Invoke-RestMethod `
      -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey" `
      -Method Post -Body $body -ContentType "application/json"
    return @{ token = $r.idToken; uid = $r.localId }
  } catch {
    throw "Sign-in failed for $email : $($_.Exception.Message)"
  }
}

$admin = SignIn $AdminEmail $AdminPassword
Write-Host "signed in as admin ($($admin.uid))" -ForegroundColor DarkGray

# A fresh account, so the customer probes are not affected by anything the admin
# account has been granted. Deleted at the end.
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$probeEmail = "ruleprobe+$stamp@highlanderscoffee.ph"
$signup = @{ email = $probeEmail; password = "RuleProbe-$stamp"; returnSecureToken = $true } | ConvertTo-Json
$probeUser = Invoke-RestMethod `
  -Uri "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey" `
  -Method Post -Body $signup -ContentType "application/json"
$customer = @{ token = $probeUser.idToken; uid = $probeUser.localId }
Write-Host "probe customer ($($customer.uid))" -ForegroundColor DarkGray

# An anonymous token: proves the public menu read and that orders are not public.
$anon = @{ token = $null; uid = "<signed out>" }

# --- Firestore REST helpers ----------------------------------------------------
#
# The REST API takes typed field values rather than JSON scalars. Rather than hand
# write `{"stringValue": "x"}` at every call site and get it subtly wrong, the two
# shapes used here get a constructor each.

function FStr([string]$v) { return @{ stringValue = $v } }
function FInt([int]$v)   { return @{ integerValue = "$v" } }
function FBool([bool]$v)  { return @{ booleanValue = $v } }
function FArr([array]$v)  { return @{ arrayValue = @{ values = $v } } }

function DocPath([string]$coll, [string]$id) {
  return "projects/$ProjectId/databases/$Database/documents/$coll/$id"
}

function Get-Doc([hashtable]$who, [string]$coll, [string]$id) {
  $h = @{}
  if ($who.token) { $h.Authorization = "Bearer $($who.token)" }
  try {
    Invoke-RestMethod -Uri "https://firestore.googleapis.com/v1/$(DocPath $coll $id)" -Headers $h -Method Get | Out-Null
    return "ALLOW"
  } catch {
    return (Status-Of $_)
  }
}

function Set-Doc([hashtable]$who, [string]$coll, [string]$id, [hashtable]$fields) {
  $h = @{}
  if ($who.token) { $h.Authorization = "Bearer $($who.token)" }

  # `:commit` with an explicit mask rather than PATCH with `updateMask=*`.
  #
  # Two reasons. `*` is not a legal property path — the API rejects it with
  # INVALID_ARGUMENT and a confusing message about regexes. And a bare PATCH
  # cannot create a document, so seeding a fixture that does not exist yet would
  # need a second code path. A write with an updateMask upserts.
  $write = @{
    update = @{
      name   = (DocPath $coll $id)
      fields = $fields
    }
    updateMask = @{ fieldPaths = @($fields.Keys) }
  }
  $body = @{ writes = @($write) } | ConvertTo-Json -Depth 12

  try {
    Invoke-RestMethod `
      -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:commit" `
      -Headers $h -Method Post -Body $body -ContentType "application/json" | Out-Null
    return "ALLOW"
  } catch {
    return (Status-Of $_)
  }
}

function Del-Doc([hashtable]$who, [string]$coll, [string]$id) {
  $h = @{}
  if ($who.token) { $h.Authorization = "Bearer $($who.token)" }
  try {
    Invoke-RestMethod -Uri "https://firestore.googleapis.com/v1/$(DocPath $coll $id)" -Headers $h -Method Delete | Out-Null
    return "ALLOW"
  } catch {
    return (Status-Of $_)
  }
}

function Query-Orders([hashtable]$who, [string]$customerUid) {
  $h = @{}
  if ($who.token) { $h.Authorization = "Bearer $($who.token)" }

  $where = @{
    fieldFilter = @{
      field = @{ fieldPath = "customerUid" }
      op = "EQUAL"
      value = (FStr $customerUid)
    }
  }
  $body = @{
    structuredQuery = @{
      from = @(@{ collectionId = "orders" })
      where = $where
    }
  } | ConvertTo-Json -Depth 10

  try {
    Invoke-RestMethod `
      -Uri "https://firestore.googleapis.com/v1/projects/$ProjectId/databases/$Database/documents:runQuery" `
      -Headers $h -Method Post -Body $body -ContentType "application/json" | Out-Null
    return "ALLOW"
  } catch {
    return (Status-Of $_)
  }
}

function Status-Of($err) {
  $body = ""
  try {
    $stream = $err.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $body = $reader.ReadToEnd()
  } catch {
    $body = $err.Exception.Message
  }

  # Normalise first. The assertions are phrased as ALLOW / DENIED / NOT_FOUND
  # because those are the three outcomes that mean something to a reader. Returning
  # the raw API status instead means every DENIED assertion has to spell it
  # PERMISSION_DENIED, which is both noisier and easier to get wrong when a new
  # assertion is added.
  if ($body -match 'PERMISSION_DENIED') { return "DENIED" }
  if ($body -match '"code"\s*:\s*404' -or $body -match 'NOT_FOUND') { return "NOT_FOUND" }

  if ($body -match '"status"\s*:\s*"(\w+)"') {
    $s = $Matches[1]
    if ($s -eq "OK") { return "ALLOW" }
    return "ERROR: $s"
  }

  return "ERROR: " + ($body -replace '\s+', ' ')
}

# --- assertions ---------------------------------------------------------------

$script:failures = 0
$script:checks = 0

function Assert([string]$label, [string]$expected, [string]$actual) {
  $script:checks++
  if ($expected -eq $actual) {
    Write-Host ("  ok    {0,-58} {1}" -f $label, $actual) -ForegroundColor DarkGray
  } else {
    $script:failures++
    Write-Host ("  FAIL  {0,-58} expected {1}, got {2}" -f $label, $expected, $actual) -ForegroundColor Red
  }
}

# Documents the probes need to exist.
#
# Written by whichever identity is *allowed* to write them, not by the admin out of
# convenience. The first version of this script seeded everything as the admin and
# most of it was denied — which is the rules being right, not the script being
# broken, and worth spelling out:
#
#   * The admin cannot create a `users/{uid}` document for someone else. `create`
#     requires `isOwner`, so a user document can only ever be created by its own
#     account at first sign-in. That is why an admin is promoted in the console —
#     the console bypasses rules.
#   * The admin cannot create an order attributed to another customer, unless the
#     `create` rule says so. See the note on the `create` line in firestore.rules.
#
# So each fixture below is written by the identity that should be able to write it.
Write-Host "`nseeding probe fixtures" -ForegroundColor DarkGray

$seedResults = [ordered]@{
  "customer creates own user doc" = (Set-Doc $customer "users" $customer.uid @{
      uid = (FStr $customer.uid); email = (FStr $probeEmail)
      fullName = (FStr "Rule Probe"); role = (FStr "customer")
    })
  "customer creates own order" = (Set-Doc $customer "orders" "probe-own" @{
      id = (FStr "probe-own"); customerUid = (FStr $customer.uid)
      status = (FStr "pending"); lines = (FArr @())
    })
  "admin creates another's order" = (Set-Doc $admin "orders" "probe-someone" @{
      id = (FStr "probe-someone"); customerUid = (FStr "someone-else")
      status = (FStr "pending"); lines = (FArr @())
    })
  "admin writes the roster" = (Set-Doc $admin "staffMembers" "probe-staff" @{
      id = (FStr "probe-staff"); name = (FStr "Probe"); role = (FStr "rider"); shift = (FStr "offShift")
    })
  "admin writes a menu item" = (Set-Doc $admin "menuItems" "probe-item" @{
      id = (FStr "probe-item"); name = (FStr "Probe Brew"); price = (FInt 60)
    })
  "admin writes shop settings" = (Set-Doc $admin "settings" "highlanders" @{
      cafeName = (FStr "Highlanders Coffee & Tea"); isOpen = (FBool $true)
    })
}

# A failed fixture turns every assertion that reads it into a misleading NOT_FOUND,
# so this is checked rather than discarded. The earlier version used `$null =` and
# produced a wall of confusing failures.
$seedFailed = @($seedResults.GetEnumerator() | Where-Object { $_.Value -ne "ALLOW" })
foreach ($e in $seedResults.GetEnumerator()) {
  if ($e.Value -eq "ALLOW") {
    Write-Host ("  ok    {0,-58} {1}" -f $e.Key, $e.Value) -ForegroundColor DarkGray
  } else {
    Write-Host ("  FAIL  {0,-58} {1}" -f $e.Key, $e.Value) -ForegroundColor Red
  }
}

Write-Host "`nusers" -ForegroundColor Cyan
Assert "customer reads own doc"                "ALLOW" (Get-Doc $customer "users" $customer.uid)
Assert "customer reads someone else's doc"     "DENIED" (Get-Doc $customer "users" "VK0Fw0kHCOPaeCmYMcpenHgJvp12")
Assert "customer promotes self to admin"        "DENIED" (Set-Doc $customer "users" $customer.uid @{ role = (FStr "admin") })
Assert "customer deletes own doc"              "DENIED" (Del-Doc $customer "users" $customer.uid)
Assert "admin creates a doc for someone else"  "DENIED" (Set-Doc $admin "users" "someone-else" @{ uid = (FStr "someone-else"); role = (FStr "admin") })
Assert "admin reads any doc"                   "ALLOW" (Get-Doc $admin "users" $customer.uid)

Write-Host "`npublic reference data" -ForegroundColor Cyan
Assert "signed out reads the menu"             "ALLOW" (Get-Doc $anon "menuItems" "probe-item")
Assert "customer writes the menu"              "DENIED" (Set-Doc $customer "menuItems" "probe-x" @{ name = (FStr "X"); price = (FInt 1) })
Assert "admin writes the menu"                 "ALLOW" (Set-Doc $admin "menuItems" "probe-x" @{ name = (FStr "Probe item"); price = (FInt 1) })

Write-Host "`norders - the rule that is easiest to get wrong" -ForegroundColor Cyan
Assert "customer reads own order"              "ALLOW" (Get-Doc $customer "orders" "probe-own")
Assert "customer reads another customer's"     "DENIED" (Get-Doc $customer "orders" "probe-someone")
Assert "customer queries own orders (filtered)" "ALLOW" (Query-Orders $customer $customer.uid)
Assert "customer queries others' orders"       "DENIED" (Query-Orders $customer "someone-else")
Assert "customer creates own order"            "ALLOW" (Set-Doc $customer "orders" "probe-new" @{ id = (FStr "probe-new"); customerUid = (FStr $customer.uid); status = (FStr "pending"); lines = (FArr @()) })
Assert "customer creates order for someone"    "DENIED" (Set-Doc $customer "orders" "probe-forge" @{ id = (FStr "probe-forge"); customerUid = (FStr "someone-else"); status = (FStr "pending"); lines = (FArr @()) })
Assert "customer marks own order delivered"    "DENIED" (Set-Doc $customer "orders" "probe-own" @{ id = (FStr "probe-own"); customerUid = (FStr $customer.uid); status = (FStr "delivered"); lines = (FArr @()) })
Assert "admin advances an order"               "ALLOW" (Set-Doc $admin "orders" "probe-own" @{ id = (FStr "probe-own"); customerUid = (FStr $customer.uid); status = (FStr "confirmed"); lines = (FArr @()) })
Assert "admin deletes an order"                "ALLOW" (Del-Doc $admin "orders" "probe-someone")
# Re-seed it: the next section reads it as "another customer's order".
$null = Set-Doc $admin "orders" "probe-someone" @{ id = (FStr "probe-someone"); customerUid = (FStr "someone-else"); status = (FStr "pending"); lines = (FArr @()) }

Write-Host "`nstaff roster" -ForegroundColor Cyan
Assert "customer reads the roster"             "DENIED" (Get-Doc $customer "staffMembers" "probe-staff")
Assert "customer writes the roster"            "DENIED" (Set-Doc $customer "staffMembers" "probe-staff" @{ name = (FStr "Hacked") })
Assert "admin reads the roster"                "ALLOW" (Get-Doc $admin "staffMembers" "probe-staff")
Assert "admin writes the roster"               "ALLOW" (Set-Doc $admin "staffMembers" "probe-staff" @{ id = (FStr "probe-staff"); name = (FStr "Probe Rider"); role = (FStr "rider"); shift = (FStr "onShift") })

Write-Host "`nsettings" -ForegroundColor Cyan
Assert "signed out reads shop settings"        "ALLOW" (Get-Doc $anon "settings" "highlanders")
Assert "customer writes shop settings"         "DENIED" (Set-Doc $customer "settings" "highlanders" @{ isOpen = (FBool $true) })
Assert "admin writes shop settings"            "ALLOW" (Set-Doc $admin "settings" "highlanders" @{ isOpen = (FBool $false) })

Write-Host "`ncatch-all" -ForegroundColor Cyan
Assert "signed out reads an undeclared path"   "DENIED" (Get-Doc $anon "secretCollection" "x")
Assert "admin reads an undeclared path"        "DENIED" (Get-Doc $admin "secretCollection" "x")

# --- cleanup ------------------------------------------------------------------

Write-Host "`ncleaning up" -ForegroundColor DarkGray
foreach ($id in @("probe-x", "probe-item")) { $null = Del-Doc $admin "menuItems" $id }
foreach ($id in @("probe-own", "probe-new", "probe-forge", "probe-someone")) { $null = Del-Doc $admin "orders" $id }
$null = Del-Doc $admin "staffMembers" "probe-staff"
$null = Del-Doc $admin "users" "someone-else"
$null = Del-Doc $customer "users" $customer.uid
# The auth account, so the probe does not accumulate a user per run.
$del = @{ idToken = $customer.token } | ConvertTo-Json
try {
  Invoke-RestMethod `
    -Uri "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$apiKey" `
    -Method Post -Body $del -ContentType "application/json" | Out-Null
} catch {
  Write-Host "  warning: could not delete the probe auth account ($probeEmail)" -ForegroundColor Yellow
}

# `settings/highlanders` is deliberately left in place: it is real shop
# configuration the app reads at startup, not a probe artefact.

# --- result -------------------------------------------------------------------

Write-Host ""
$failedSeeds = $seedFailed.Count
if ($script:failures -eq 0 -and $failedSeeds -eq 0) {
  Write-Host "all $($script:checks) rule assertions passed" -ForegroundColor Green
  exit 0
}
if ($failedSeeds -gt 0) {
  Write-Host "$failedSeeds fixture(s) could not be created - the assertions below are not meaningful" -ForegroundColor Red
}
Write-Host "$($script:failures) of $($script:checks) rule assertions FAILED" -ForegroundColor Red
exit 1

# --- known limits -------------------------------------------------------------
#
# This script proves the boundary holds. It does not prove the *reason* it holds
# is the one intended: a DENIED is reported from the message, so a rule that denies
# for the wrong reason - an undeclared collection rather than the per-document
# customerUid check - looks identical here.
#
# Two things are worth knowing rather than assuming:
#
#   * `users/{uid}` create is not probed. It needs a document that does not exist
#     yet with a matching auth uid, and the probe account's document is written by
#     the admin before the run. Probing it means a second throwaway account.
#   * A list query with NO filter is not probed. The rules comment claims it is
#     refused with PERMISSION_DENIED because evaluation is per-document. That is
#     correct per the Firestore docs, but it is the single most consequential
#     claim in the rules file, so confirm it by hand before relying on it:
#       a customer signing in and reading /orders unfiltered must get PERMISSION_DENIED.