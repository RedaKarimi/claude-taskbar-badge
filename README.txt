Claude Code Taskbar Badge
=========================

Per-tab status badge for Claude Code sessions in Windows Terminal.

States:
  BLUE   = working (Claude generating)
  YELLOW = waiting (needs your input/permission)
  GREEN  = done (response complete)

Badge follows focused tab. No badge when focused tab is not Claude.

Requirements:
  - Windows 10/11
  - Windows Terminal
  - Claude Code installed (%USERPROFILE%\.claude exists)

Install:
  powershell -ExecutionPolicy Bypass -File install.ps1

Restart Claude Code session after install.

Pick notification sound (optional, after install):
  powershell -ExecutionPolicy Bypass -File "%USERPROFILE%\.claude\scripts\taskbar-sound-picker.ps1"

Uninstall:
  powershell -ExecutionPolicy Bypass -File uninstall.ps1

Build .exe (optional):
  Install-Module ps2exe -Scope CurrentUser
  Invoke-PS2EXE install.ps1 install.exe
  Invoke-PS2EXE uninstall.ps1 uninstall.exe
