param(
    [Parameter(Mandatory)][ValidateSet('working','waiting','done')]
    [string]$State
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-ClaudePid {
    $cur = $PID
    for ($i = 0; $i -lt 12; $i++) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur"
        if (-not $p) { return 0 }
        if ($p.Name -eq 'claude.exe') { return $cur }
        $cur = [int]$p.ParentProcessId
        if ($cur -le 0) { return 0 }
    }
    return 0
}

$claudePid = Get-ClaudePid
& "$PSScriptRoot\taskbar-log.ps1" -Source 'state' -Msg "called state=$State claudePid=$claudePid hookPid=$PID"
if ($claudePid -eq 0) {
    & "$PSScriptRoot\taskbar-log.ps1" -Source 'state' -Msg 'no claude.exe in parent chain, exiting'
    exit 0
}

$dir = Join-Path $env:TEMP 'claude-badges'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

$file = Join-Path $dir "$claudePid.state"
$tmp = "$file.tmp"
Set-Content -Path $tmp -Value $State -NoNewline -Encoding ASCII
Move-Item -Path $tmp -Destination $file -Force
& "$PSScriptRoot\taskbar-log.ps1" -Source 'state' -Msg "wrote $file = $State"

# On 'working' (user submitted prompt = this tab is focused), refresh tab mapping
if ($State -eq 'working') {
    try {
        # Walk up to find WindowsTerminal.exe HWND
        $cur = $PID
        $hwnd = [IntPtr]::Zero
        for ($i = 0; $i -lt 12; $i++) {
            $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur"
            if (-not $p) { break }
            if ($p.Name -eq 'WindowsTerminal.exe') {
                $hwnd = (Get-Process -Id $cur).MainWindowHandle
                break
            }
            $cur = [int]$p.ParentProcessId
            if ($cur -le 0) { break }
        }
        if ($hwnd -ne [IntPtr]::Zero) {
            Add-Type -AssemblyName UIAutomationClient
            Add-Type -AssemblyName UIAutomationTypes
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
            if ($root) {
                $tabCond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                    [System.Windows.Automation.ControlType]::TabItem)
                $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
                $selPattern = [System.Windows.Automation.SelectionItemPattern]::Pattern
                $rid = $null
                foreach ($tab in $tabs) {
                    try {
                        $sip = $tab.GetCurrentPattern($selPattern)
                        if ($sip -and $sip.Current.IsSelected) { $rid = ($tab.GetRuntimeId() -join ','); break }
                    } catch {}
                }
                if ($rid) {
                    $hwndLong = $hwnd.ToInt64()
                    $mapFile = Join-Path $env:TEMP "claude-tabmap-$hwndLong.json"
                    $map = @{}
                    if (Test-Path $mapFile) {
                        try {
                            $obj = Get-Content $mapFile -Raw | ConvertFrom-Json
                            foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = $p.Value }
                        } catch {}
                    }
                    $map[$rid] = $claudePid
                    $tmp = "$mapFile.tmp"
                    ($map | ConvertTo-Json -Compress) | Set-Content -Path $tmp -Encoding ASCII -NoNewline
                    Move-Item -Path $tmp -Destination $mapFile -Force
                    & "$PSScriptRoot\taskbar-log.ps1" -Source 'state' -Msg "refreshed mapping $rid -> $claudePid"
                }
            }
        }
    } catch {
        & "$PSScriptRoot\taskbar-log.ps1" -Source 'state' -Msg "mapping refresh error: $_"
    }
}

# Play sound if configured for this state (detached so it survives hook exit)
$configPath = Join-Path $PSScriptRoot 'taskbar-sound.json'
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        $prop = $config.PSObject.Properties[$State]
        if ($prop -and $prop.Value -and (Test-Path $prop.Value)) {
            & "$PSScriptRoot\taskbar-play-sound.ps1" -Path $prop.Value
        }
    } catch {}
}
