param([Parameter(Mandatory)][string]$Path)

$ErrorActionPreference = 'SilentlyContinue'
if (-not (Test-Path $Path)) { exit 0 }

Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
    "(New-Object System.Media.SoundPlayer '$Path').PlaySync()"
) | Out-Null
