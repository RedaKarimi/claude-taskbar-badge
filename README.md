# Claude Taskbar Badge

Per-tab status dots on the Windows Terminal taskbar icon for [Claude Code](https://claude.com/claude-code) sessions. Tells you at a glance which tab is working, which is waiting on you, and which is done.

![demo placeholder](docs/demo.gif)

## What it does

You run multiple Claude Code sessions in Windows Terminal tabs. Without something like this you have no idea which one needs your attention without clicking through them. This adds a colored dot to the taskbar icon that reflects the focused tab's Claude session.

Three states:

- **Blue** — working. Claude is generating or running tools.
- **Yellow** — waiting. Claude is asking permission or asking you a question.
- **Green** — done. Response complete, nothing to do.

No dot means the focused tab is not a Claude session (e.g. PowerShell).

The dot follows the active tab. Switch tabs and the badge updates within ~300ms. Close the window or kill Claude and the dot clears itself.

## Install

Run `install.exe` from the release zip (or `powershell -ExecutionPolicy Bypass -File install.ps1`). The installer:

1. Drops the PowerShell scripts into `%USERPROFILE%\.claude\scripts\`
2. Adds hooks to `%USERPROFILE%\.claude\settings.json` (preserves anything already there)
3. Offers to pick a notification sound for `waiting` and `done` states

After install, restart Claude Code. The badge starts working on the next session.

Windows SmartScreen may complain about the unsigned exe. Click "More info" → "Run anyway". Or just run the `.ps1` directly.

## Uninstall

`uninstall.exe`. Removes the scripts, strips the hooks from `settings.json`, deletes the temp state files, kills any running watcher processes.

## How it works

Three pieces, one per Terminal window:

- **state.ps1** runs on every Claude Code hook (UserPromptSubmit, PreToolUse, PostToolUse, Stop, Notification). It writes the current state (working/waiting/done) to a file in `%TEMP%\claude-badges\<pid>.state`.
- **watcher.ps1** is a hidden PowerShell process that polls the Terminal's focused tab via UI Automation every 300ms. It reads the matching session's state file and sets the taskbar overlay icon through `ITaskbarList3::SetOverlayIcon`.
- **watchdog.ps1** sits on each Claude session's PID. When that PID dies (window close, Ctrl+C, crash), it deletes the state file so the watcher clears the badge.

Each Claude session registers itself in `%TEMP%\claude-tabmap-<hwnd>.json` mapping a UI Automation tab runtime ID to the session's PID. UserPromptSubmit refreshes that mapping every time you send a prompt, which is what keeps it correct after you reorder tabs.

## Sound

The installer asks if you want notification sounds. The picker shows every `.wav` in `C:\Windows\Media`. Use arrow keys to move, **Space** to preview, **S** to save, **Q** to quit. Left and Right jump 12 entries at a time.

To change sounds later:

```powershell
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\scripts\taskbar-sound-picker.ps1 -Target waiting
powershell -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\scripts\taskbar-sound-picker.ps1 -Target done
```

The config lives at `%USERPROFILE%\.claude\scripts\taskbar-sound.json`. Delete it to silence everything.

## Requirements

- Windows 10 or 11
- Windows Terminal (other terminals will not work, see below)
- PowerShell 5.1 (ships with Windows, no install needed)
- Claude Code installed at the default location

## Why Windows Terminal only

The badge attaches to a window handle via the Win32 taskbar API. Per-tab tracking needs UI Automation to find which tab is selected, which requires a host that exposes its tab strip through UIA. Windows Terminal does. ConHost (the classic console window) does not have tabs at all. ConEmu, Cmder, and similar wrappers were not tested and will probably break.

## Known limitations

- Multiple tabs in the same window share one taskbar icon. The badge reflects the *focused* tab. Switching tabs updates the badge, but you can only see one session's state at a time per window. If you want truly independent badges, open separate Terminal windows (Ctrl+Shift+N) instead of tabs.
- First time you install, you have to restart Claude Code for the SessionStart hook to fire. The watcher does not start until then.
- The UIA poll runs every 300ms. There is a small lag when you switch tabs.

## Debugging

If the badge does not appear, check the log:

```
%TEMP%\claude-taskbar-debug.log
```

Useful checks:

- Are the watcher and watchdog processes alive? `Get-Process powershell | Where-Object { $_.CommandLine -match 'taskbar-watch' }`
- Is the state file getting written? `Get-Content $env:TEMP\claude-badges\*.state`
- Does the mapping point to the right PID? `Get-Content $env:TEMP\claude-tabmap-*.json`

The watcher logs every state change it applies. If the log shows the right state but the icon does not change, your Windows Terminal HWND probably changed (close-and-reopened window). Restart Claude Code to re-register.

## Building from source

You only need `install.ps1` to install — the `.exe` is just `ps2exe`-compiled for convenience.

```powershell
Install-Module ps2exe -Scope CurrentUser
Invoke-PS2EXE install.ps1 install.exe
Invoke-PS2EXE uninstall.ps1 uninstall.exe
```

The PowerShell sources for everything that runs on your machine are in `scripts/`. Read them. Nothing is obfuscated.

## License

MIT. See `LICENSE`.
