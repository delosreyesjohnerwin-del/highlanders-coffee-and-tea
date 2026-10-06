# Taps and types on the device by matching what is on screen.
#
#   powershell -File tool\drive.ps1 -Find "Email" -Action tap
#   powershell -File tool\drive.ps1 -Find "Email" -Action type -Text "a@b.com"
#   powershell -File tool\drive.ps1 -Find "Log In" -Action tap -Wait 4
#
# ## Why matching on text rather than hard-coded coordinates
#
# Hard-coded tap points are the obvious shortcut and they rot silently. The
# density override on this device is 272 rather than the physical 320, so every
# coordinate in dp is 15% smaller than it looks on paper, and a keyboard appearing
# moves everything above it. A coordinate recorded once is wrong the moment either
# changes, and nothing fails — the tap just lands on the wrong widget or nowhere.
#
# So every action re-reads the tree and resolves the centre from the live bounds.
# Slower, and it cannot silently tap the wrong thing.
param(
  [Parameter(Mandatory = $true)][string]$Find,
  [ValidateSet("tap", "type", "swipeup", "exists")][string]$Action = "tap",
  [string]$Text = "",
  [int]$Wait = 0,
  [int]$Index = 0,
  [switch]$Exact
)

$ErrorActionPreference = "Continue"

$platformTools = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools"
if (-not (Test-Path $platformTools)) { throw "platform-tools not found at $platformTools" }
$env:Path = "$platformTools;$env:Path"

function Get-DensityScale {
  $t = (& adb shell wm density) -join " "
  if ($t -match "Override density:\s*(\d+)") { $d = [int]$Matches[1] }
  elseif ($t -match "Physical density:\s*(\d+)") { $d = [int]$Matches[1] }
  else { throw "no density in: $t" }
  return ($d / 160.0)
}

function Get-Tree([double]$scale) {
  & adb shell uiautomator dump /sdcard/ui.xml | Out-Null
  & adb pull /sdcard/ui.xml $env:TEMP\hl-drive.xml | Out-Null
  $xml = [xml](Get-Content "$env:TEMP\hl-drive.xml" -Raw)

  # content-desc first, then text. Flutter puts a TextField's semantics label in
  # content-desc, while plain Text nodes can land in either depending on how the
  # widget was composed, so both are searched and the label wins ties.
  $out = @()
  foreach ($n in $xml.SelectNodes("//node[@content-desc!='' or @text!='']")) {
    $desc = $n.GetAttribute("content-desc")
    $txt = $n.GetAttribute("text")
    $label = if ($desc) { $desc } else { $txt }
    if (-not $label) { continue }

    $b = $n.GetAttribute("bounds")
    if ($b -notmatch '\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]') { continue }
    $l = [int]$Matches[1]; $t2 = [int]$Matches[2]
    $r = [int]$Matches[3]; $b2 = [int]$Matches[4]

    $out += [pscustomobject]@{
      Label  = $label
      Text   = $txt
      CX     = [int](($l + $r) / 2)
      CY     = [int](($t2 + $b2) / 2)
      Wdp    = [math]::Round(($r - $l) / $scale, 1)
      Hdp    = [math]::Round(($b2 - $t2) / $scale, 1)
      Clickable = ($n.GetAttribute("clickable") -eq "true")
    }
  }
  return $out
}

$scale = Get-DensityScale
$tree = Get-Tree $scale

if ($Exact) {
  $matches = @($tree | Where-Object { $_.Label -ceq $Find })
} else {
  $matches = @($tree | Where-Object { $_.Label -like "*$Find*" })
}

if ($matches.Count -eq 0) {
  Write-Host "NOT FOUND: $Find"
  Write-Host ""
  Write-Host "on screen:"
  foreach ($n in $tree) { Write-Host ("  {0,4} x {1,-6}  @x={2,-5} y={3,-6}  {4}" -f $n.Wdp, $n.Hdp, [math]::Round($n.CX / $scale, 0), [math]::Round($n.CY / $scale, 0), $n.Label) }
  exit 1
}

if ($Index -ge $matches.Count) {
  Write-Host "only $($matches.Count) match(es) for '$Find', wanted index $Index"
  exit 1
}

$target = $matches[$Index]
Write-Host ("matched [{0}]: {1}  @x={2} y={3}  {4} x {5} dp" -f $Index, $target.Label, [math]::Round($target.CX / $scale, 0), [math]::Round($target.CY / $scale, 0), $target.Wdp, $target.Hdp)

switch ($Action) {
  "exists" { Write-Host "EXISTS" }
  "tap" {
    & adb shell input tap $target.CX $target.CY | Out-Null
    Write-Host "tapped"
  }
  "type" {
    if (-not $Text) { throw "-Text is required for -Action type" }
    # `input text` treats space as a separator and mangles several shell
    # metacharacters, so it is given each word separately.
    foreach ($word in ($Text -split '\s+')) {
      & adb shell input text $word | Out-Null
    }
    Write-Host "typed $((($Text -split '\s+') | Measure-Object).Count) word(s)"
  }
  "swipeup" {
    & adb shell input swipe 360 1300 360 500 300 | Out-Null
    Write-Host "swiped up"
  }
}

if ($Wait -gt 0) {
  Start-Sleep -Seconds $Wait
  Write-Host "waited ${Wait}s"
}
