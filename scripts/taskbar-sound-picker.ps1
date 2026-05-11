param([ValidateSet('waiting','done')][string]$Target = 'waiting')

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$mediaDir = 'C:\Windows\Media'
$wavs = Get-ChildItem -Path $mediaDir -Filter '*.wav' | Sort-Object Name
if ($wavs.Count -eq 0) {
    Write-Host "No .wav files in $mediaDir" -ForegroundColor Red
    exit 1
}

$items = @()
$items += [PSCustomObject]@{ Idx = 0; Name = '<NONE - silent>'; Path = '' }
$i = 1
foreach ($w in $wavs) {
    $items += [PSCustomObject]@{ Idx = $i; Name = $w.Name; Path = $w.FullName }
    $i++
}

$configPath = Join-Path $PSScriptRoot 'taskbar-sound.json'
$selected = 0
if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        $cur = $cfg.PSObject.Properties[$Target]
        if ($cur) {
            for ($k = 0; $k -lt $items.Count; $k++) {
                if ($items[$k].Path -eq $cur.Value) { $selected = $k; break }
            }
        }
    } catch {}
}

$viewSize = 12
$inner = 64
$offset = [Math]::Max(0, $selected - [int]($viewSize / 2))
if ($offset + $viewSize -gt $items.Count) { $offset = [Math]::Max(0, $items.Count - $viewSize) }
$playing = -1
$firstRender = $true

# audio playback state
$audioPos = 0.0
$audioDur = 0.0

$BORDER = 'DarkGray'
$ACCENT = 'Cyan'
$NORMAL = 'Gray'
$DIM    = 'DarkGray'

function WrapLine {
    param([string]$Text, [string]$Color = $NORMAL)
    Write-Host -NoNewline ('|') -ForegroundColor $BORDER
    Write-Host -NoNewline $Text.PadRight($inner) -ForegroundColor $Color
    Write-Host ('|') -ForegroundColor $BORDER
}

function Render {
    if ($script:firstRender) {
        Clear-Host
        [Console]::CursorVisible = $false
        $script:firstRender = $false
    } else {
        try { [Console]::SetCursorPosition(0, 0) } catch {}
    }
    $top    = '+' + ('-' * $inner) + '+'
    $sep    = '+' + ('-' * $inner) + '+'

    Write-Host $top -ForegroundColor $BORDER
    WrapLine ('  Claude  -  ' + $Target.ToUpper() + ' sound') $ACCENT
    Write-Host $sep -ForegroundColor $BORDER
    WrapLine ''

    $end = [Math]::Min($offset + $viewSize, $items.Count)
    for ($k = $offset; $k -lt $end; $k++) {
        $it = $items[$k]
        $marker = if ($k -eq $playing) { '>' } else { ' ' }
        $line = ('   {0}  {1,3}   {2}' -f $marker, $it.Idx, $it.Name)
        if ($line.Length -gt $inner - 1) { $line = $line.Substring(0, $inner - 2) + '~' }
        $line = $line.PadRight($inner)

        Write-Host -NoNewline ('|') -ForegroundColor $BORDER
        if ($k -eq $selected) {
            Write-Host -NoNewline $line -BackgroundColor DarkCyan -ForegroundColor White
        } elseif ($k -eq $playing) {
            Write-Host -NoNewline $line -ForegroundColor Yellow
        } else {
            Write-Host -NoNewline $line -ForegroundColor $NORMAL
        }
        Write-Host ('|') -ForegroundColor $BORDER
    }
    for ($pad = $end - $offset; $pad -lt $viewSize; $pad++) { WrapLine '' }

    WrapLine ''

    # Audio playback bar — shown only when playing
    if ($playing -ge 0 -and $audioDur -gt 0) {
        $barW = $inner - 24
        $pct = if ($audioDur -gt 0) { [Math]::Min(1.0, $audioPos / $audioDur) } else { 0 }
        $pos = [int]($pct * $barW)
        if ($pos -gt $barW) { $pos = $barW }
        $filled = '#' * $pos
        $empty  = '.' * ($barW - $pos)
        $time = ('{0,4:N1}s / {1,-4:N1}s' -f $audioPos, $audioDur)

        Write-Host -NoNewline ('|') -ForegroundColor $BORDER
        Write-Host -NoNewline '  [' -ForegroundColor $DIM
        Write-Host -NoNewline $filled -ForegroundColor Green
        Write-Host -NoNewline $empty -ForegroundColor $DIM
        Write-Host -NoNewline ']  ' -ForegroundColor $DIM
        Write-Host -NoNewline $time -ForegroundColor $ACCENT
        $used = 3 + 1 + $barW + 1 + 2 + $time.Length
        $padA = [Math]::Max(0, $inner - $used)
        Write-Host -NoNewline ((' ' * $padA)) -ForegroundColor $NORMAL
        Write-Host ('|') -ForegroundColor $BORDER
    } else {
        WrapLine ''
    }

    # Counter centered
    $counter = ('{0,3} / {1,-3}' -f ($selected + 1), $items.Count)
    $cpad = [Math]::Max(0, [int](($inner - $counter.Length) / 2))
    Write-Host -NoNewline ('|') -ForegroundColor $BORDER
    Write-Host -NoNewline ((' ' * $cpad)) -ForegroundColor $NORMAL
    Write-Host -NoNewline $counter -ForegroundColor $ACCENT
    $rpad = [Math]::Max(0, $inner - $cpad - $counter.Length)
    Write-Host -NoNewline ((' ' * $rpad)) -ForegroundColor $NORMAL
    Write-Host ('|') -ForegroundColor $BORDER

    WrapLine ''
    Write-Host $sep -ForegroundColor $BORDER

    $btns = @(' < Prev  ', '  Play   ', ' Next >  ', '  Save   ', '  Quit   ')
    $keys = @('  Left   ', '  Space  ', '  Right  ', '   S     ', '   Q     ')

    Write-Host -NoNewline ('|') -ForegroundColor $BORDER
    Write-Host -NoNewline ' '
    foreach ($b in $btns) {
        Write-Host -NoNewline '[' -ForegroundColor $DIM
        Write-Host -NoNewline $b -ForegroundColor White
        Write-Host -NoNewline '] ' -ForegroundColor $DIM
    }
    $btnLen = 1 + ($btns.Count * ($btns[0].Length + 3))
    Write-Host -NoNewline ((' ' * [Math]::Max(0, $inner - $btnLen))) -ForegroundColor $NORMAL
    Write-Host ('|') -ForegroundColor $BORDER

    Write-Host -NoNewline ('|') -ForegroundColor $BORDER
    Write-Host -NoNewline ' '
    foreach ($k in $keys) {
        Write-Host -NoNewline ' ' -ForegroundColor $DIM
        Write-Host -NoNewline $k -ForegroundColor $DIM
        Write-Host -NoNewline '  ' -ForegroundColor $DIM
    }
    $keyLen = 1 + ($keys.Count * ($keys[0].Length + 3))
    Write-Host -NoNewline ((' ' * [Math]::Max(0, $inner - $keyLen))) -ForegroundColor $NORMAL
    Write-Host ('|') -ForegroundColor $BORDER

    Write-Host ('+' + ('-' * $inner) + '+') -ForegroundColor $BORDER
}

function Get-WavDuration {
    param([string]$Path)
    $fs = [IO.File]::OpenRead($Path)
    try {
        $br = New-Object IO.BinaryReader $fs
        $riff = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($riff -ne 'RIFF') { return 0 }
        [void]$br.ReadInt32()
        $wave = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($wave -ne 'WAVE') { return 0 }
        $byteRate = 0
        $dataSize = 0
        while ($fs.Position -lt $fs.Length - 8) {
            $chunkId = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            $chunkSize = $br.ReadInt32()
            if ($chunkId -eq 'fmt ') {
                [void]$br.ReadInt16()
                [void]$br.ReadInt16()
                [void]$br.ReadInt32()
                $byteRate = $br.ReadInt32()
                $remaining = $chunkSize - 12
                if ($remaining -gt 0) { [void]$br.ReadBytes($remaining) }
            } elseif ($chunkId -eq 'data') {
                $dataSize = $chunkSize
                break
            } else {
                [void]$br.ReadBytes($chunkSize)
            }
        }
        if ($byteRate -gt 0) { return [double]$dataSize / [double]$byteRate }
        return 0
    } finally { $fs.Close() }
}

function PlayPreview {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) {
        $script:playing = -1
        return
    }

    $dur = 0
    try { $dur = Get-WavDuration $Path } catch { $dur = 0 }
    if ($dur -le 0) { $dur = 2.0 }

    $script:audioDur = $dur
    $script:audioPos = 0

    $player = New-Object System.Media.SoundPlayer $Path
    try { $player.Play() } catch {}

    # Full render once to redraw row markers
    Render

    # Audio-bar row in Render: top(1) + title(1) + sep(1) + pad(1) + viewSize + pad(1) = 4 + viewSize + 1
    $audioRow = 5 + $viewSize
    $esc = [char]27
    $cReset = "$esc[0m"
    $cBorder = "$esc[90m"
    $cDim    = "$esc[90m"
    $cGreen  = "$esc[92m"
    $cAccent = "$esc[96m"

    $barW = $inner - 24

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $dur) {
        $script:audioPos = $sw.Elapsed.TotalSeconds
        $pct = [Math]::Min(1.0, $script:audioPos / $dur)
        $pos = [int]($pct * $barW)
        if ($pos -gt $barW) { $pos = $barW }
        $filled = '#' * $pos
        $empty  = '.' * ($barW - $pos)
        $time = ('{0,4:N1}s / {1,-4:N1}s' -f $script:audioPos, $dur)
        $used = 3 + 1 + $barW + 1 + 2 + $time.Length
        $padA = [Math]::Max(0, $inner - $used)

        $line = "$cBorder|$cReset  [$cGreen$filled$cDim$empty$cReset]  $cAccent$time$cReset$(' ' * $padA)$cBorder|$cReset"

        try {
            [Console]::SetCursorPosition(0, $audioRow)
            [Console]::Write($line)
        } catch {}

        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape' -or $k.Key -eq 'Spacebar') { break }
        }
        Start-Sleep -Milliseconds 50
    }
    try { $player.Stop() } catch {}

    $script:playing = -1
    $script:audioDur = 0
    $script:audioPos = 0
}

try {
while ($true) {
    Render
    $key = [Console]::ReadKey($true)
    switch ($key.Key) {
        'UpArrow' {
            if ($selected -gt 0) { $selected-- }
            if ($selected -lt $offset) { $offset = $selected }
        }
        'DownArrow' {
            if ($selected -lt $items.Count - 1) { $selected++ }
            if ($selected -ge $offset + $viewSize) { $offset = $selected - $viewSize + 1 }
        }
        'LeftArrow' {
            $selected = [Math]::Max(0, $selected - $viewSize)
            $offset = [Math]::Max(0, $offset - $viewSize)
        }
        'RightArrow' {
            $selected = [Math]::Min($items.Count - 1, $selected + $viewSize)
            $offset = [Math]::Min([Math]::Max(0, $items.Count - $viewSize), $offset + $viewSize)
        }
        'Home' { $selected = 0; $offset = 0 }
        'End'  { $selected = $items.Count - 1; $offset = [Math]::Max(0, $items.Count - $viewSize) }
        'Spacebar' {
            $playing = $selected
            PlayPreview -Path $items[$selected].Path
        }
        default {
            $c = [char]::ToLower($key.KeyChar)
            if ($c -eq 's') {
                $current = $items[$selected]
                $config = @{}
                if (Test-Path $configPath) {
                    try {
                        $existing = Get-Content $configPath -Raw | ConvertFrom-Json
                        foreach ($p in $existing.PSObject.Properties) { $config[$p.Name] = $p.Value }
                    } catch {}
                }
                $config[$Target] = $current.Path
                ($config | ConvertTo-Json -Compress) | Set-Content -Path $configPath -Encoding ASCII -NoNewline
                [Console]::CursorVisible = $true
                Clear-Host
                Write-Host ''
                Write-Host (" Saved [$Target]: " + $current.Name) -ForegroundColor Green
                exit 0
            }
            if ($c -eq 'q') {
                [Console]::CursorVisible = $true
                Clear-Host
                Write-Host ' Cancelled.'
                exit 0
            }
        }
    }
}
} finally {
    [Console]::CursorVisible = $true
}
