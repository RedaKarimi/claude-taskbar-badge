$ErrorActionPreference = 'SilentlyContinue'

# Read stdin JSON from Claude Code Notification hook
$stdin = [Console]::In.ReadToEnd()

# Log every notification for tuning (last 50 entries kept)
$logPath = Join-Path $env:TEMP 'claude-notification-log.txt'
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
"$ts $stdin" | Add-Content -Path $logPath -Encoding UTF8
# Trim log
if ((Get-Item $logPath -ErrorAction SilentlyContinue).Length -gt 102400) {
    $tail = Get-Content $logPath -Tail 50
    Set-Content -Path $logPath -Value $tail -Encoding UTF8
}

$ntype = ''
try {
    $obj = $stdin | ConvertFrom-Json
    $ntype = "$($obj.notification_type)"
} catch {}

& "$PSScriptRoot\taskbar-log.ps1" -Source 'notify' -Msg "type=$ntype hookPid=$PID"

if ($ntype -eq 'idle_prompt') {
    & "$PSScriptRoot\taskbar-log.ps1" -Source 'notify' -Msg 'skipped idle_prompt'
    exit 0
}

& "$PSScriptRoot\taskbar-log.ps1" -Source 'notify' -Msg "-> setting waiting"
& "$PSScriptRoot\taskbar-state.ps1" -State waiting
