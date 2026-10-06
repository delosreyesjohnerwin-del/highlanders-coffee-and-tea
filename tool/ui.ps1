# Dumps the on-screen widget tree as plain text, with dp sizes.
#
#   powershell -File tool\ui.ps1
#   powershell -File tool\ui.ps1 -WidthOnly
#
# Why a script rather than adb commands: reading a Flutter UI means parsing
# `content-desc` and `bounds` out of the uiautomator dump, and bounds come as
# `[l,t][r,b]` in physical pixels. Dividing by density on the way through is
# where the numbers stop being trustworthy, and a wrong width makes a "fits at
# 360dp" claim false in a way that is easy to miss. Doing it in one place means
# the arithmetic is written once.
#
# Flutter exposes semantics here, not text nodes, so most content arrives as
# content-desc. Plain Text widgets can appear in either.
param(
  [switch]$NoSize,
  [switch]$All,
  [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

$platformTools = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools"
if (-not (Test-Path $platformTools)) { throw "platform-tools not found at $platformTools" }
$env:Path = "$platformTools;$env:Path"

$pkg = "com.highlanderscoffee.highlanders_coffee"

# adb writes progress to stderr even on success, and PowerShell promotes that
# to an error under Stop. Relaxed for the adb calls; the script's own `throw`s
# still mean something because they are detected, not inferred from adb's exit
# noise. The pull's stderr is separately redirected to $null below.
$ErrorActionPreference = "Continue"

# Density, not dpi: the override wins over the physical value, and the phone can
# have been resized. Reading the override is the difference between "fits" and
# "overflows" being a real claim.
$densityText = (& adb shell wm density) -join " "
if ($densityText -match "Override density:\s*(\d+)") {
  $density = [int]$Matches[1]
} elseif ($densityText -match "Physical density:\s*(\d+)") {
  $density = [int]$Matches[1]
} else {
  throw "could not read density from: $densityText"
}
$scale = $density / 160.0

$sizeText = (& adb shell wm size) -join " "
if ($sizeText -notmatch "(\d+)x(\d+)") { throw "could not read size from: $sizeText" }
$screenWdp = [math]::Round([int]$Matches[1] / $scale, 1)
$screenHdp = [math]::Round([int]$Matches[2] / $scale, 1)

Write-Host ("screen: {0} x {1} dp  (density {2}, scale {3})" -f $screenWdp, $screenHdp, $density, [math]::Round($scale, 2))

if ($OutFile) { if (Test-Path $OutFile) { Remove-Item $OutFile -Force } }

# Redirected to $null rather than left to the error stream. adb prints
# "1 file pulled" on stderr as its success message, and PowerShell turns a
# native stderr write into a NativeCommandError -- so the pull's good news was
# being reported as the script's failure. Anything genuinely wrong is caught by
# the file check below, which is a real detection rather than an inference from
# adb's chatter.
$null = & adb shell uiautomator dump /sdcard/ui.xml 2>$null
$null = & adb pull /sdcard/ui.xml $env:TEMP\hl-ui.xml 2>$null

# uiautomator writes the dump to the device first; a stale file from a previous
# dump would silently describe the old screen, so the pull is verified rather
# than trusted.
if (-not (Test-Path $env:TEMP\hl-ui.xml)) { throw "uiautomator dump did not produce a readable file" }

$xml = [xml](Get-Content "$env:TEMP\hl-ui.xml" -Raw)

function Convert-Bounds([string]$bounds) {
  # "[l,t][r,b]" -> @{ L = ..; T = ..; W = ..; H = ..; C = .. } in dp
  if ($bounds -notmatch '\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]') {
    return @{ L = 0; T = 0; W = 0; H = 0; C = 0 }
  }
  $l = [int]$Matches[1]; $t = [int]$Matches[2]
  $r = [int]$Matches[3]; $b = [int]$Matches[4]
  return @{
    L = [math]::Round($l / $scale, 1)
    T = [math]::Round($t / $scale, 1)
    W = [math]::Round(($r - $l) / $scale, 1)
    H = [math]::Round(($b - $t) / $scale, 1)
    C = [math]::Round((($l + $r) / 2) / $scale, 1)
  }
}

Write-Host ""
Write-Host "--- content-desc (Flutter semantics) ---"
$nodes = $xml.SelectNodes("//node[@content-desc!='']")
if ($nodes.Count -eq 0) { Write-Host "  (none)" }

foreach ($n in $nodes) {
  $d = $n.GetAttribute("content-desc")
  $g = Convert-Bounds $n.GetAttribute("bounds")
  if ($NoSize) {
    Write-Host "  $d"
  } else {
    Write-Host ("  {0,4} x {1,-6}  @x={2,-6} y={3,-6}  {4}" -f $g.W, $g.H, $g.L, $g.T, $d)
  }
}

$textNodes = $xml.SelectNodes("//node[@text!='']")
if ($textNodes.Count -gt 0) {
  Write-Host ""
  Write-Host "--- text ---"
  foreach ($n in $textNodes) {
    $g = Convert-Bounds $n.GetAttribute("bounds")
    if ($NoSize) {
      Write-Host "  $($n.GetAttribute('text'))"
    } else {
      Write-Host ("  {0,4} x {1,-6}  @x={2,-6} y={3,-6}  {4}" -f $g.W, $g.H, $g.L, $g.T, $n.GetAttribute('text'))
    }
  }
}

if ($All) {
  # The labelled nodes above are only the ones Flutter gave a description to. An
  # empty TextField exposes neither text nor content-desc -- its labelText lives
  # in the decoration, which uiautomator does not surface -- so the fields a
  # driver needs to tap are precisely the ones missing from both lists.
  #
  # This mode prints the structural nodes too: class, whether they are
  # tappable/focusable, and what is left of their label. It is the difference
  # between "the fields are not there" and "the fields are there and unlabelled",
  # which look identical from the outside and have very different fixes.
  Write-Host ""
  Write-Host "--- all nodes (class | clickable | focusable | label) ---"
  foreach ($n in $xml.SelectNodes("//node")) {
    $g = Convert-Bounds $n.GetAttribute("bounds")
    $desc = $n.GetAttribute("content-desc")
    $txt = $n.GetAttribute("text")
    $label = if ($desc) { $desc } elseif ($txt) { $txt } else { "-" }
    $cls = $n.GetAttribute("class")
    if (-not $cls) { $cls = "?" }
    $short = $cls -replace '^android\.', '' -replace '^androidx\.', ''
    Write-Host ("  {0,5}x{1,-5} @{2,-6},{3,-6} {4,-26} {5,-1} {6,-1}  {7}" -f `
      $g.W, $g.H, $g.L, $g.T, $short,
      ($n.GetAttribute("clickable")[0]), ($n.GetAttribute("focusable")[0]), $label)
  }
}

if ($OutFile) { Move-Item $env:TEMP\hl-ui.xml $OutFile -Force; Write-Host ""; Write-Host "saved: $OutFile" }

# adb reports "1 file pulled" on stderr even when everything worked, and that
# reaches PowerShell as a native stderr write. Without this, the script exits 1
# on a completely successful dump -- so a caller that checks $? sees a failure
# for a run that printed exactly what was asked for.
exit 0
