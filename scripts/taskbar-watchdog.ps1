param(
    [Parameter(Mandatory)][int]$ClaudePid,
    [Parameter(Mandatory)][long]$Hwnd
)

$ErrorActionPreference = 'SilentlyContinue'

if ($ClaudePid -le 0) { exit 1 }

$stateFile = Join-Path $env:TEMP "claude-badges\$ClaudePid.state"
$mapFile = Join-Path $env:TEMP "claude-tabmap-$Hwnd.json"

while ($true) {
    $p = Get-Process -Id $ClaudePid -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Seconds 2
}

# Cleanup state
Remove-Item -Path $stateFile -Force -ErrorAction SilentlyContinue

# Cleanup mapping entry by PID
if (Test-Path $mapFile) {
    try {
        $obj = Get-Content $mapFile -Raw | ConvertFrom-Json
        $map = @{}
        foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        $toRemove = @()
        foreach ($k in $map.Keys) {
            if ([int]$map[$k] -eq $ClaudePid) { $toRemove += $k }
        }
        foreach ($k in $toRemove) { $map.Remove($k) }
        if ($map.Count -gt 0) {
            $tmp = "$mapFile.tmp"
            ($map | ConvertTo-Json -Compress) | Set-Content -Path $tmp -Encoding ASCII -NoNewline
            Move-Item -Path $tmp -Destination $mapFile -Force
        } else {
            Remove-Item -Path $mapFile -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}
