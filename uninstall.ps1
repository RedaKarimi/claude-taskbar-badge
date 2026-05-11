# Claude Code Taskbar Badge - Uninstaller

$ErrorActionPreference = 'Continue'

Write-Host 'Claude Code Taskbar Badge uninstaller' -ForegroundColor Cyan

# Stop watcher and watchdogs
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'taskbar-(watcher|watchdog|session-start|state)' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "  killed pid $($_.ProcessId)" }

# Remove temp state
Remove-Item "$env:TEMP\claude-badges" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\claude-watcher-*.pid" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\claude-tabmap-*.json" -Force -ErrorAction SilentlyContinue

# Remove scripts
$scriptsDir = Join-Path $env:USERPROFILE '.claude\scripts'
foreach ($f in @('taskbar-state.ps1','taskbar-session-start.ps1','taskbar-watchdog.ps1','taskbar-watcher.ps1','taskbar-sound-picker.ps1','taskbar-sound.json','taskbar-play-sound.ps1','taskbar-notification.ps1')) {
    $p = Join-Path $scriptsDir $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  removed $p" }
}

# Strip hooks from settings.json
$settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.hooks) {
        foreach ($evt in @('SessionStart','UserPromptSubmit','Stop','Notification')) {
            if ($settings.hooks.PSObject.Properties[$evt]) {
                $matches = $false
                foreach ($h in $settings.hooks.$evt) {
                    foreach ($cmd in $h.hooks) {
                        if ($cmd.command -match 'taskbar-(state|session-start)') { $matches = $true }
                    }
                }
                if ($matches) {
                    $settings.hooks.PSObject.Properties.Remove($evt)
                    Write-Host "  removed hook $evt"
                }
            }
        }
    }
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
}

Write-Host 'Uninstall complete.' -ForegroundColor Green
Write-Host 'Press Enter to close...'
Read-Host | Out-Null
