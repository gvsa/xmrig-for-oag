# Checks scripts/oag/start.bat on Windows without mining: every run uses --dry-run.
#
#   pwsh tests/oag/start_bat_test.ps1 [-Bat path\to\start.bat]
#
# Exit code 0 means every check passed.

param(
    [string]$Bat = "scripts/oag/start.bat"
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path $Bat)) { Write-Host "no such file: $Bat"; exit 1 }
$Bat = (Resolve-Path $Bat).Path
$failures = 0
$checks = 0

# A well-formed mainnet address from a throwaway key; only printed, never mined to.
$Addr = "oag1qxd46y2zmzw97u3chqtz47ltej02ks8q4vppu2v00zmzx7hm2mhts8a5mfs"
$Orange = "-o mine.orange.gen.nz:1920 -u $Addr -a rx/oag"
$VSLabs = "-o oagnode.vslabs.co.in:1919 -u $Addr -a rx/oag"

function Check([bool]$ok, [string]$what, $r = $null) {
    $script:checks++
    if ($ok) {
        Write-Host "  ok    $what"
    } else {
        $script:failures++
        Write-Host "  FAIL  $what"
        if ($r) { Write-Host "        exit code $($r.Code)"; Write-Host ($r.Out -replace "(?m)^", "        | ") }
    }
}

# Runs start.bat --dry-run with the given environment and stdin; returns exit code and output.
function Run([string]$bat, [hashtable]$envs, [string]$stdin = "") {
    foreach ($name in "OAG_ADDRESS", "OAG_POOL") {
        if ($envs.ContainsKey($name)) { Set-Item "Env:$name" $envs[$name] } else { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    }
    $out = $stdin | & cmd.exe /d /c $bat --dry-run 2>&1 | Out-String
    $code = $LASTEXITCODE
    $cmd = ($out -split "`r?`n" | Where-Object { $_ -match '^".*xmrig\.exe" ' } | Select-Object -First 1)
    return @{ Code = $code; Out = $out; Cmd = [string]$cmd }
}

Write-Host "file"
$bytes = [System.IO.File]::ReadAllBytes($Bat)
Check (-not ($bytes | Where-Object { $_ -gt 127 })) "start.bat is ASCII only"
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
Check (($text -split "`r`n").Count -eq ($text -split "`n").Count) "start.bat uses CRLF line endings"
Check (-not ($text -match "(?i)official")) "start.bat does not say 'official'"

Write-Host "pool 1"
$r = Run $Bat @{ OAG_ADDRESS = $Addr; OAG_POOL = "1" }
Check ($r.Code -eq 0) "exit code 0" $r
Check ($r.Cmd.Contains($Orange)) "uses Orange Pool" $r
Check (-not $r.Cmd.Contains("oagnode.vslabs.co.in")) "does not use VSLabs" $r
Check ($r.Cmd.EndsWith("-a rx/oag --cpu-priority 0 --pause-on-battery")) "idle priority and pause on battery" $r
Check ($r.Out.Contains("Dry run: xmrig was not started.")) "does not start xmrig" $r

Write-Host "pool 2"
$r = Run $Bat @{ OAG_ADDRESS = $Addr; OAG_POOL = "2" }
Check ($r.Code -eq 0) "exit code 0" $r
Check ($r.Cmd.Contains($VSLabs)) "uses VSLabs" $r
Check (-not $r.Cmd.Contains("mine.orange.gen.nz")) "does not use Orange Pool" $r

Write-Host "pool 3 (auto, random order)"
$orders = @{}
for ($i = 0; $i -lt 20; $i++) {
    $r = Run $Bat @{ OAG_ADDRESS = $Addr; OAG_POOL = "3" }
    if ($r.Code -ne 0 -or -not $r.Cmd.Contains($Orange) -or -not $r.Cmd.Contains($VSLabs)) {
        Check $false "run $i lists both pools with exit code 0" $r
        break
    }
    $first = if ($r.Cmd.IndexOf($Orange) -lt $r.Cmd.IndexOf($VSLabs)) { "orange-first" } else { "vslabs-first" }
    $orders[$first] = 1 + [int]$orders[$first]
}
Check ($orders.Count -eq 2) "both orders appear over 20 runs ($(($orders.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))"

Write-Host "addresses that must be refused"
$bad = [ordered]@{
    "oag2 prefix"      = "oag2" + $Addr.Substring(4)
    "uppercase OAG1"   = "OAG1" + $Addr.Substring(4)
    "too short"        = "oag1qqqqqq"
    "too long"         = "oag1" + ("q" * 90)
    "letter b"         = $Addr.Substring(0, 10) + "b" + $Addr.Substring(11)
    "uppercase inside" = $Addr.Substring(0, 10) + "Q" + $Addr.Substring(11)
    "testnet toag1"    = "t" + $Addr
    "ampersand"        = $Addr + "&echo INJECTED"
}
foreach ($case in $bad.GetEnumerator()) {
    $r = Run $Bat @{ OAG_ADDRESS = $case.Value; OAG_POOL = "1" }
    Check ($r.Code -eq 2 -and $r.Out.Contains("is not an OAG address") -and -not $r.Out.Contains("INJECTED")) "refuses: $($case.Key)" $r
}

Write-Host "other inputs"
$r = Run $Bat @{ OAG_ADDRESS = "  $Addr  "; OAG_POOL = "1" }
Check ($r.Code -eq 0 -and $r.Cmd.Contains($Orange)) "trims spaces around the address" $r
$r = Run $Bat @{ OAG_ADDRESS = $Addr; OAG_POOL = "4" }
Check ($r.Code -eq 2 -and $r.Out.Contains("Unknown pool choice")) "refuses pool choice 4" $r

# The prompt and the saved address, in a scratch copy so no oag-address.txt is left behind.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("start-bat-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $copy = Join-Path $tmp "start.bat"
    Copy-Item $Bat $copy

    $r = Run $copy @{ OAG_POOL = "2" } $Addr
    Check ($r.Code -eq 0 -and $r.Cmd.Contains($VSLabs)) "takes a pasted address" $r
    Check ($r.Out.Contains("https://wallet.oagcoin.org/")) "points to the browser wallet" $r
    Check (-not (Test-Path (Join-Path $tmp "oag-address.txt"))) "dry run saves nothing"

    $r = Run $copy @{ OAG_POOL = "2" } "oag2nope"
    Check ($r.Code -eq 2 -and $r.Out.Contains("That is not an OAG address") -and $r.Out.Contains("Giving up")) "refuses a bad pasted address and gives up without input" $r

    Set-Content -Path (Join-Path $tmp "oag-address.txt") -Value $Addr -Encoding ascii
    $r = Run $copy @{ OAG_POOL = "1" }
    Check ($r.Code -eq 0 -and $r.Cmd.Contains($Orange) -and $r.Out.Contains("Using the address saved in oag-address.txt")) "uses the saved address" $r
    Check ($r.Out.Contains("delete oag-address.txt")) "says how to change the address" $r

    Set-Content -Path (Join-Path $tmp "oag-address.txt") -Value "not-an-address" -Encoding ascii
    $r = Run $copy @{ OAG_POOL = "1" }
    Check ($r.Code -eq 2 -and $r.Out.Contains("oag-address.txt does not hold an OAG address")) "asks again when the saved address is bad" $r
} finally {
    Remove-Item -Recurse -Force $tmp
}

Write-Host "$checks checks, $failures failed"
exit ([int]($failures -ne 0))
