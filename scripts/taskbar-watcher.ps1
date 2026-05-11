param([Parameter(Mandatory)][long]$Hwnd)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$src = @'
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("ea1afb91-9e28-4b86-90e9-9e9f8a5eefaf")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITaskbarList3 {
    [PreserveSig] int HrInit();
    [PreserveSig] int AddTab(IntPtr hwnd);
    [PreserveSig] int DeleteTab(IntPtr hwnd);
    [PreserveSig] int ActivateTab(IntPtr hwnd);
    [PreserveSig] int SetActiveAlt(IntPtr hwnd);
    [PreserveSig] int MarkFullscreenWindow(IntPtr hwnd, bool fFullscreen);
    [PreserveSig] int SetProgressValue(IntPtr hwnd, ulong ullCompleted, ulong ullTotal);
    [PreserveSig] int SetProgressState(IntPtr hwnd, int tbpFlags);
    [PreserveSig] int RegisterTab(IntPtr hwndTab, IntPtr hwndMDI);
    [PreserveSig] int UnregisterTab(IntPtr hwndTab);
    [PreserveSig] int SetTabOrder(IntPtr hwndTab, IntPtr hwndInsertBefore);
    [PreserveSig] int SetTabActive(IntPtr hwndTab, IntPtr hwndMDI, uint dwReserved);
    [PreserveSig] int ThumbBarAddButtons(IntPtr hwnd, uint cButtons, IntPtr pButton);
    [PreserveSig] int ThumbBarUpdateButtons(IntPtr hwnd, uint cButtons, IntPtr pButton);
    [PreserveSig] int ThumbBarSetImageList(IntPtr hwnd, IntPtr himl);
    [PreserveSig] int SetOverlayIcon(IntPtr hwnd, IntPtr hIcon, [MarshalAs(UnmanagedType.LPWStr)] string pszDescription);
    [PreserveSig] int SetThumbnailTooltip(IntPtr hwnd, [MarshalAs(UnmanagedType.LPWStr)] string pszTip);
    [PreserveSig] int SetThumbnailClip(IntPtr hwnd, IntPtr prcClip);
}

public static class Native {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
}

public static class TaskbarBadge {
    static ITaskbarList3 tlb;
    public static void Init() {
        Type t = Type.GetTypeFromCLSID(new Guid("56FDF344-FD6D-11d0-958A-006097C9A090"));
        object o = Activator.CreateInstance(t);
        tlb = (ITaskbarList3)o;
        tlb.HrInit();
    }
    public static int Set(IntPtr hwnd, IntPtr hIcon, string desc) {
        if (tlb == null) Init();
        return tlb.SetOverlayIcon(hwnd, hIcon, desc);
    }
}
'@

if (-not ('TaskbarBadge' -as [type])) { Add-Type -TypeDefinition $src }

[TaskbarBadge]::Init()
$hwndPtr = [IntPtr]$Hwnd

function New-DotIcon {
    param([System.Drawing.Color]$Fill)
    $size = 32
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush($Fill)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 3)
    $g.FillEllipse($brush, 2, 2, $size - 4, $size - 4)
    $g.DrawEllipse($pen, 2, 2, $size - 4, $size - 4)
    $g.Dispose(); $brush.Dispose(); $pen.Dispose()
    $h = $bmp.GetHicon()
    $bmp.Dispose()
    return $h
}

$icons = @{
    working = New-DotIcon ([System.Drawing.Color]::FromArgb(50, 130, 246))
    waiting = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 180, 0))
    done    = New-DotIcon ([System.Drawing.Color]::FromArgb(40, 200, 80))
}
$descs = @{ working = 'Claude working'; waiting = 'Claude waiting'; done = 'Claude done' }

$badgeDir = Join-Path $env:TEMP 'claude-badges'
$mapFile = Join-Path $env:TEMP "claude-tabmap-$Hwnd.json"
$pidFile = Join-Path $env:TEMP "claude-watcher-$Hwnd.pid"
Set-Content -Path $pidFile -Value $PID -NoNewline -Encoding ASCII

$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwndPtr)
$tabCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::TabItem
)
$selPattern = [System.Windows.Automation.SelectionItemPattern]::Pattern

$lastState = ''
$lastPid = ''

try {
    while ($true) {
        if (-not [Native]::IsWindow($hwndPtr)) { break }

        $newState = $null
        $newPid = ''

        # Find selected tab via UIA
        $selRid = $null
        try {
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)
            foreach ($tab in $tabs) {
                try {
                    $sip = $tab.GetCurrentPattern($selPattern)
                    if ($sip -and $sip.Current.IsSelected) {
                        $selRid = ($tab.GetRuntimeId() -join ',')
                        break
                    }
                } catch {}
            }
        } catch {
            # UIA tree may have refreshed; reacquire root
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwndPtr)
        }

        if ($selRid -and (Test-Path $mapFile)) {
            try {
                $obj = Get-Content $mapFile -Raw | ConvertFrom-Json
                $prop = $obj.PSObject.Properties[$selRid]
                if ($prop) {
                    $newPid = "$($prop.Value)"
                    $stateFile = Join-Path $badgeDir "$newPid.state"
                    if (Test-Path $stateFile) {
                        $newState = (Get-Content $stateFile -Raw).Trim()
                    }
                }
            } catch {}
        }

        if ($newState -ne $lastState -or $newPid -ne $lastPid) {
            & "$PSScriptRoot\taskbar-log.ps1" -Source 'watcher' -Msg "hwnd=$Hwnd selRid=$selRid pid=$newPid state=$newState"
            if ($newState -and $icons.ContainsKey($newState)) {
                [void][TaskbarBadge]::Set($hwndPtr, $icons[$newState], $descs[$newState])
            } else {
                [void][TaskbarBadge]::Set($hwndPtr, [IntPtr]::Zero, $null)
            }
            $lastState = $newState
            $lastPid = $newPid
        }

        Start-Sleep -Milliseconds 300
    }
}
finally {
    [void][TaskbarBadge]::Set($hwndPtr, [IntPtr]::Zero, $null)
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
}
