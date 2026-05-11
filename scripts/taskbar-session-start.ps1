$ErrorActionPreference = 'SilentlyContinue'

# Walk parent chain to find claude.exe AND WindowsTerminal.exe
$cur = $PID
$claudePid = 0
$hwnd = [IntPtr]::Zero

for ($i = 0; $i -lt 12; $i++) {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur"
    if (-not $p) { break }
    if ($p.Name -eq 'claude.exe' -and $claudePid -eq 0) {
        $claudePid = $cur
    }
    if ($p.Name -eq 'WindowsTerminal.exe') {
        $proc = Get-Process -Id $cur
        if ($proc) { $hwnd = $proc.MainWindowHandle }
        break
    }
    $cur = [int]$p.ParentProcessId
    if ($cur -le 0) { break }
}

& "$PSScriptRoot\taskbar-log.ps1" -Source 'sess-start' -Msg "claudePid=$claudePid hwnd=$($hwnd.ToInt64()) hookPid=$PID"

if ($claudePid -eq 0 -or $hwnd -eq [IntPtr]::Zero) {
    & "$PSScriptRoot\taskbar-log.ps1" -Source 'sess-start' -Msg 'missing claudePid or hwnd, exit'
    exit 0
}

# Initial state file: done (idle)
$dir = Join-Path $env:TEMP 'claude-badges'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$stateFile = Join-Path $dir "$claudePid.state"
Set-Content -Path $stateFile -Value 'done' -NoNewline -Encoding ASCII

# Register selected tab RuntimeId -> ClaudePid via UIA
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
$rid = $null
if ($root) {
    $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TabItem
    )
    $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
    $selPattern = [System.Windows.Automation.SelectionItemPattern]::Pattern
    foreach ($tab in $tabs) {
        try {
            $sip = $tab.GetCurrentPattern($selPattern)
            if ($sip -and $sip.Current.IsSelected) {
                $rid = ($tab.GetRuntimeId() -join ',')
                break
            }
        } catch {}
    }
}

& "$PSScriptRoot\taskbar-log.ps1" -Source 'sess-start' -Msg "selected tab rid=$rid"

if ($rid) {
    $hwndLong = $hwnd.ToInt64()
    $mapFile = Join-Path $env:TEMP "claude-tabmap-$hwndLong.json"
    $map = @{}
    if (Test-Path $mapFile) {
        try {
            $obj = Get-Content $mapFile -Raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
        } catch { $map = @{} }
    }
    $map[$rid] = $claudePid
    $tmp = "$mapFile.tmp"
    ($map | ConvertTo-Json -Compress) | Set-Content -Path $tmp -Encoding ASCII -NoNewline
    Move-Item -Path $tmp -Destination $mapFile -Force
}

$scriptDir = $PSScriptRoot
$hwndLong = $hwnd.ToInt64()

# Spawn detached watchdog (one per session)
Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
    '-File', "$scriptDir\taskbar-watchdog.ps1",
    '-ClaudePid', $claudePid,
    '-Hwnd', $hwndLong
) | Out-Null

# Ensure one watcher per Terminal window
$watcherPidFile = Join-Path $env:TEMP "claude-watcher-$hwndLong.pid"
$needsWatcher = $true
if (Test-Path $watcherPidFile) {
    $existingPid = (Get-Content $watcherPidFile -Raw).Trim()
    if ($existingPid -match '^\d+$') {
        $existing = Get-Process -Id ([int]$existingPid) -ErrorAction SilentlyContinue
        if ($existing) { $needsWatcher = $false }
    }
}

if ($needsWatcher) {
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
        '-File', "$scriptDir\taskbar-watcher.ps1",
        '-Hwnd', $hwndLong
    ) | Out-Null
}
