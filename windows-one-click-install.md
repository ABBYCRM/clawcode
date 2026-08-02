# Windows One-Click Install

The single-line installer for Claw Code on Windows.

## The one-liner

Open **PowerShell** or **cmd** as a normal user (no admin needed), paste this:

```cmd
curl -L -o "%TEMP%\claw-setup.cmd" "https://raw.githubusercontent.com/ABBYCRM/clawcode/main/setup-windows.cmd" && "%TEMP%\claw-setup.cmd"
```

Equivalent PowerShell one-liner:

```powershell
irm https://raw.githubusercontent.com/ABBYCRM/clawcode/main/setup-windows.cmd -OutFile "$env:TEMP\claw-setup.cmd"; & "$env:TEMP\claw-setup.cmd"
```

## What it does

| Step | Action |
|---|---|
| 1 | Checks `git`, `python`, installs `rust` if missing |
| 2 | Clones `ABBYCRM/clawcode` → `%LOCALAPPDATA%\ClawCode` |
| 3 | Builds the Rust binary (`cargo build --release`, 3-10 min) |
| 4 | Opens a **new window** to run `scripts/setup-providers.sh` interactively (paste your Bitdeer + NVIDIA NIM keys) |
| 5 | Writes `claw.cmd` wrapper (loads `.env`, runs the binary) and `launch-hidden.vbs` (detached background launcher) |
| 6 | Creates **two desktop shortcuts** + one Start Menu shortcut |

## Two shortcuts it creates

### 1. `Claw Code.lnk` (interactive console)
- **Target:** `cmd.exe /k claw.cmd`
- Opens a visible cmd window with the claw REPL
- Closing the window exits claw (normal CLI behavior)

### 2. `Claw Code (Background).lnk` (hidden, survives close)
- **Target:** `wscript.exe //B launch-hidden.vbs`
- Runs `claw prompt --continue` in a **hidden window** with no parent process
- **Survives closing any visible cmd window** — the VBS launcher has no parent to inherit the close signal from
- Stop it: `taskkill /IM claw.exe` (or Task Manager → claw.exe → End task)

## File layout after install

```
%LOCALAPPDATA%\ClawCode\
├── claw.cmd                    # wrapper: loads .env, runs binary
├── launch-hidden.vbs           # detached VBS launcher
├── .env                        # your real API keys (NEVER commit)
├── .claw\
│   └── settings.local.json     # local provider config (NEVER commit)
├── rust\
│   └── target\release\
│       └── claw.exe            # the actual binary
└── scripts\
    ├── setup-providers.sh      # interactive provider setup
    ├── setup-providers.cmd     # Windows wrapper
    ├── test-providers.sh       # smoke test
    └── test-providers.cmd      # Windows wrapper
```

## Re-running setup

```cmd
"%LOCALAPPDATA%\ClawCode\scripts\setup-providers.cmd"
```

## Updating later

```cmd
cd /d %LOCALAPPDATA%\ClawCode
git pull
cargo build --release --manifest-path rust\Cargo.toml
```

## Uninstalling

```cmd
rmdir /s /q "%LOCALAPPDATA%\ClawCode"
del "%USERPROFILE%\Desktop\Claw Code.lnk"
del "%USERPROFILE%\Desktop\Claw Code (Background).lnk"
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Claw Code.lnk"
```
