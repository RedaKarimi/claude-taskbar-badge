param([string]$Source, [string]$Msg)

$logPath = Join-Path $env:TEMP 'claude-taskbar-debug.log'
$ts = Get-Date -Format 'HH:mm:ss.fff'
"$ts [$Source] $Msg" | Add-Content -Path $logPath -Encoding UTF8

# Trim if > 200KB
try {
    if ((Get-Item $logPath -ErrorAction SilentlyContinue).Length -gt 204800) {
        $tail = Get-Content $logPath -Tail 200
        Set-Content -Path $logPath -Value $tail -Encoding UTF8
    }
} catch {}
