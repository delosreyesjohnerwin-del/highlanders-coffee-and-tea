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
  [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

$platformTools = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools"
if (-not (Test-Path $platformTools)) { throw "platform-tools not found at $platformTools" }
$env:Path = "$platformTools;$env:Path"

$pkg = "com.highlanderscoffee.highlanders_coffee"

# adb writes its progress lines to stderr even on success — "1 file pulled" is a
# success message, not a failure. With ErrorActionPreference left at Stop, PowerShell
# promotes that to a terminating error and the script dies reporting a successful
# pull as a crash. Relaxed for the adb calls only; the throw statements below stay
# meaningful because those are real failures we detect ourselves.
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

& adb shell uiautomator dump /sdcard/ui.xml | Out-Null
& adb pull /sdcard/ui.xml $env:TEMP\hl-ui.xml | Out-Null

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

if ($OutFile) { Move-Item $env:TEMP\hl-ui.xml $OutFile -Force; Write-Host ""; Write-Host "saved: $OutFile" }
