@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  Claw Code - One-Click Windows Installer
REM  Source: https://github.com/ABBYCRM/clawcode
REM
REM  This version AUTO-INSTALLS git, python, and rust if missing
REM  via winget (with direct-download fallback).
REM
REM  Two desktop shortcuts are created:
REM    1. "Claw Code"              - interactive console
REM    2. "Claw Code (Background)" - hidden VBS launcher, survives close
REM ============================================================

set "REPO=https://github.com/ABBYCRM/clawcode.git"
set "INSTALL_DIR=%LOCALAPPDATA%\ClawCode"
set "DESKTOP=%USERPROFILE%\Desktop"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "SHORTCUT=%DESKTOP%\Claw Code.lnk"
set "START_SHORTCUT=%START_MENU%\Claw Code.lnk"
set "BG_SHORTCUT=%DESKTOP%\Claw Code (Background).lnk"
set "WRAPPER=%INSTALL_DIR%\claw.cmd"
set "HIDDEN_VBS=%INSTALL_DIR%\launch-hidden.vbs"

echo.
echo ==========================================================
echo   Claw Code Setup (Windows) - One-Click Install
echo ==========================================================
echo   Install dir: %INSTALL_DIR%
echo.

REM =============================================================
REM  Phase 1: Ensure prerequisites
REM =============================================================
echo [1/6] Ensuring prerequisites...

call :ensure_winget
call :ensure_git
call :ensure_python
call :ensure_rust
call :ensure_bash

REM =============================================================
REM  Phase 2: Clone or update repo
REM =============================================================
echo.
echo [2/6] Cloning to %INSTALL_DIR%...
if not exist "%INSTALL_DIR%" (
  git clone "%REPO%" "%INSTALL_DIR%"
  if errorlevel 1 ( echo   X clone failed & exit /b 1 )
) else (
  echo   - already exists, pulling latest
  pushd "%INSTALL_DIR%"
  git pull --rebase
  popd
)

pushd "%INSTALL_DIR%"

REM =============================================================
REM  Phase 3: Build Rust binary
REM =============================================================
echo.
echo [3/6] Building Claw Code (3-10 min first time)...
if not exist "rust\target\release\claw.exe" (
  cargo build --release --manifest-path rust\Cargo.toml
  if errorlevel 1 ( echo   X build failed & popd & exit /b 1 )
) else (
  echo   - already built, skipping
)

REM =============================================================
REM  Phase 4: Interactive provider setup in a new window
REM =============================================================
echo.
echo [4/6] Launching provider setup in a new window...
echo   A new cmd window will open. Paste your Bitdeer + NVIDIA NIM keys there.
echo   When done, press any key in that window to close it.
echo.
start "Claw Code - Provider Setup" /WAIT cmd /c "cd /d %INSTALL_DIR% && bash scripts\setup-providers.sh && echo. && echo === Setup complete! Press any key to close. === && pause >nul"

REM =============================================================
REM  Phase 5: Create wrapper + VBS hidden launcher
REM =============================================================
echo.
echo [5/6] Creating wrappers...

REM claw.cmd: loads .env, runs binary
>  "%WRAPPER%" echo @echo off
>> "%WRAPPER%" echo setlocal
>> "%WRAPPER%" echo cd /d "%INSTALL_DIR%"
>> "%WRAPPER%" echo if exist ".env" (
>> "%WRAPPER%" echo     for /f "usebackq tokens=1,* delims==" %%%%a in (".env") do (
>> "%WRAPPER%" echo         set "%%%%a=%%%%b"
>> "%WRAPPER%" echo     )
>> "%WRAPPER%" echo )
>> "%WRAPPER%" echo "%INSTALL_DIR%\rust\target\release\claw.exe" %%*
>> "%WRAPPER%" echo endlocal

REM launch-hidden.vbs: detached, no parent, survives close
>  "%HIDDEN_VBS%" echo Set WshShell = CreateObject("WScript.Shell")
>> "%HIDDEN_VBS%" echo WshShell.Run chr(34) ^& "%WRAPPER%" ^& chr(34) ^& " prompt --continue", 0, False
>> "%HIDDEN_VBS%" echo Set WshShell = Nothing

REM =============================================================
REM  Phase 6: Desktop + Start Menu shortcuts
REM =============================================================
echo [6/6] Creating desktop and Start Menu shortcuts...

powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%SHORTCUT%'); ^
   $s.TargetPath = 'cmd.exe'; ^
   $s.Arguments = '/k \"\"%WRAPPER%\"\"'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.IconLocation = '%INSTALL_DIR%\rust\target\release\claw.exe,0'; ^
   $s.Description = 'Claw Code - AI coding agent (Bitdeer + NVIDIA NIM)'; ^
   $s.WindowStyle = 1; ^
   $s.Save()"

powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%BG_SHORTCUT%'); ^
   $s.TargetPath = 'wscript.exe'; ^
   $s.Arguments = '\"//B\" \"%HIDDEN_VBS%\"'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.IconLocation = '%INSTALL_DIR%\rust\target\release\claw.exe,0'; ^
   $s.Description = 'Claw Code - runs hidden, survives closing any cmd window'; ^
   $s.WindowStyle = 7; ^
   $s.Save()"

powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%START_SHORTCUT%'); ^
   $s.TargetPath = 'cmd.exe'; ^
   $s.Arguments = '/k \"\"%WRAPPER%\"\"'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.IconLocation = '%INSTALL_DIR%\rust\target\release\claw.exe,0'; ^
   $s.Description = 'Claw Code - AI coding agent'; ^
   $s.WindowStyle = 1; ^
   $s.Save()"

popd

echo.
echo ==========================================================
echo   Done! Claw Code is ready.
echo ==========================================================
echo.
echo   Desktop shortcuts:
echo     %SHORTCUT%
echo     %BG_SHORTCUT%
echo.
echo   From any cmd:
echo     "%WRAPPER%" prompt "hello"
echo.
echo   Smoke test: "%INSTALL_DIR%\scripts\test-providers.cmd"
echo.

endlocal
goto :eof

REM =============================================================
REM  Helper: ensure winget exists
REM =============================================================
:ensure_winget
where winget >nul 2>&1
if not errorlevel 1 (
  echo   OK winget
  goto :eof
)
echo   - winget missing, installing App Installer from Microsoft Store...
powershell -NoProfile -Command ^
  "Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Out-Null; ^
   if (-not (Get-AppxPackage -Name Microsoft.DesktopAppInstaller)) { ^
       Write-Host '   App Installer not installed. Downloading...' ; ^
       Invoke-WebRequest -Uri 'https://aka.ms/getwinget' -OutFile '%TEMP%\winget.msixbundle' -UseBasicParsing ; ^
       Add-AppxPackage '%TEMP%\winget.msixbundle' ^
   }"
REM Winget path is usually: %LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe
set "PATH=%LOCALAPPDATA%\Microsoft\WindowsApps;%PATH%"
where winget >nul 2>&1
if errorlevel 1 (
  echo   ! winget still not found, will fall back to direct downloads
) else (
  echo   OK winget
)
goto :eof

REM =============================================================
REM  Helper: ensure git is installed
REM =============================================================
:ensure_git
where git >nul 2>&1
if not errorlevel 1 (
  echo   OK git
  goto :eof
)
echo   - git missing, installing...
where winget >nul 2>&1
if not errorlevel 1 (
  echo     via winget (Git.Git)...
  winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
) else (
  echo     via direct download...
  curl -L -o "%TEMP%\git-installer.exe" "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"
  "%TEMP%\git-installer.exe" /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS
)
REM Add git to current session PATH (default install location)
set "PATH=C:\Program Files\Git\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin;%PATH%"
where git >nul 2>&1
if errorlevel 1 (
  echo   X git install failed
  exit /b 1
)
echo   OK git
goto :eof

REM =============================================================
REM  Helper: ensure python is installed
REM =============================================================
:ensure_python
where python >nul 2>&1
if not errorlevel 1 (
  echo   OK python
  goto :eof
)
echo   - python missing, installing...
where winget >nul 2>&1
if not errorlevel 1 (
  echo     via winget (Python.Python.3.12)...
  winget install --id Python.Python.3.12 -e --source winget --silent --accept-package-agreements --accept-source-agreements
) else (
  echo     via direct download...
  curl -L -o "%TEMP%\python-installer.exe" "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe"
  "%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_launcher=0 Include_test=0
)
REM Add python to current session PATH
set "PATH=%LOCALAPPDATA%\Programs\Python\Python312;%LOCALAPPDATA%\Programs\Python\Python312\Scripts;%PATH%"
where python >nul 2>&1
if errorlevel 1 (
  echo   X python install failed
  exit /b 1
)
echo   OK python
goto :eof

REM =============================================================
REM  Helper: ensure rust is installed
REM =============================================================
:ensure_rust
where cargo >nul 2>&1
if not errorlevel 1 (
  echo   OK rust
  goto :eof
)
echo   - rust missing, installing via rustup...
curl -sSf -o "%TEMP%\rustup-init.exe" https://win.rustup.rs/x86_64
"%TEMP%\rustup-init.exe" -y --default-toolchain stable --profile minimal
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
where cargo >nul 2>&1
if errorlevel 1 (
  echo   X rust install failed
  exit /b 1
)
echo   OK rust
goto :eof

REM =============================================================
REM  Helper: ensure bash is on PATH (comes with Git for Windows)
REM =============================================================
:ensure_bash
where bash >nul 2>&1
if not errorlevel 1 goto :eof
if exist "C:\Program Files\Git\bin\bash.exe" (
  set "PATH=C:\Program Files\Git\bin;C:\Program Files\Git\usr\bin;%PATH%"
  echo   OK bash ^(from Git install^)
  goto :eof
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
  set "PATH=C:\Program Files (x86)\Git\bin;C:\Program Files (x86)\Git\usr\bin;%PATH%"
  echo   OK bash ^(from Git install, 32-bit path^)
  goto :eof
)
echo   ! bash not found - provider setup may fail
echo     Install Git for Windows: https://git-scm.com/download/win
goto :eof
