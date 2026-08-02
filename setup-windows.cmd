@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  Claw Code - One-Click Windows Installer
REM  Source: https://github.com/ABBYCRM/clawcode
REM  What it does:
REM    1. Checks git / python / rust (installs rust if missing)
REM    2. Clones the repo to %LOCALAPPDATA%\ClawCode
REM    3. Builds the Rust binary (3-10 min first time)
REM    4. Opens a new window to run scripts\setup-providers.sh
REM       (paste your Bitdeer + NVIDIA NIM keys there)
REM    5. Creates a desktop shortcut "Claw Code.lnk"
REM    6. Creates a hidden VBS launcher so the app survives
REM       closing any visible cmd window
REM ============================================================

set "REPO=https://github.com/ABBYCRM/clawcode.git"
set "INSTALL_DIR=%LOCALAPPDATA%\ClawCode"
set "DESKTOP=%USERPROFILE%\Desktop"
set "START_MENU=%APPDATA%\Microsoft\Windows\Start Menu\Programs"
set "SHORTCUT=%DESKTOP%\Claw Code.lnk"
set "START_SHORTCUT=%START_MENU%\Claw Code.lnk"
set "WRAPPER=%INSTALL_DIR%\claw.cmd"
set "HIDDEN_VBS=%INSTALL_DIR%\launch-hidden.vbs"
set "BG_SHORTCUT=%DESKTOP%\Claw Code (Background).lnk"

echo.
echo ==========================================================
echo   Claw Code Setup (Windows)
echo ==========================================================
echo   Install dir: %INSTALL_DIR%
echo.

REM --- 1. Prerequisites ---
echo [1/6] Checking prerequisites...

set "MISSING="
where git >nul 2>&1
if errorlevel 1 ( set "MISSING=%MISSING% git" )
where python >nul 2>&1
if errorlevel 1 ( set "MISSING=%MISSING% python" )

if not "%MISSING%"=="" (
  echo.
  echo   X Missing:%MISSING%
  echo   Install them first, then re-run this script:
  echo     git:    https://git-scm.com/download/win
  echo     python: https://python.org/downloads/  (check "Add to PATH")
  exit /b 1
)
echo   OK git + python

where cargo >nul 2>&1
if errorlevel 1 (
  echo   - Rust not found, installing rustup...
  curl -sSf -o "%TEMP%\rustup-init.exe" https://win.rustup.rs/x86_64
  "%TEMP%\rustup-init.exe" -y --default-toolchain stable --profile minimal
  set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
)
echo   OK rust

where bash >nul 2>&1
if errorlevel 1 (
  echo   ! bash not on PATH. Will try Git Bash at C:\Program Files\Git\bin\bash.exe
  if exist "C:\Program Files\Git\bin\bash.exe" (
    set "PATH=C:\Program Files\Git\bin;%PATH%"
    echo   OK found Git Bash
  ) else (
    echo   X bash not found. Install Git for Windows with "Git Bash" selected.
    echo   https://git-scm.com/download/win
    pause
  )
)

REM --- 2. Clone ---
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

REM --- 3. Build ---
echo.
echo [3/6] Building Claw Code (3-10 min first time)...
if not exist "rust\target\release\claw.exe" (
  cargo build --release --manifest-path rust\Cargo.toml
  if errorlevel 1 ( echo   X build failed & popd & exit /b 1 )
) else (
  echo   - already built
)

REM --- 4. Provider setup in a new persistent window ---
echo.
echo [4/6] Launching provider setup in a new window...
echo   A new cmd window will open. Paste your Bitdeer + NVIDIA NIM keys there.
echo   When done, press any key in that window to close it.
echo.
start "Claw Code - Provider Setup" /WAIT cmd /c "cd /d %INSTALL_DIR% && bash scripts\setup-providers.sh && echo. && echo === Setup complete! === && echo Press any key to close... && pause >nul"
if errorlevel 1 (
  echo   - setup was skipped or failed. To retry:
  echo     cd /d %INSTALL_DIR% ^&^& bash scripts\setup-providers.sh
)

REM --- 5. Wrapper + hidden VBS launcher ---
echo.
echo [5/6] Creating wrappers...

REM claw.cmd wrapper: loads .env then runs the binary
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

REM Hidden VBS launcher: starts claw detached, no visible window,
REM no parent process. Survives closing ANY cmd window.
>  "%HIDDEN_VBS%" echo Set WshShell = CreateObject("WScript.Shell")
>> "%HIDDEN_VBS%" echo WshShell.Run chr(34) ^& "%WRAPPER%" ^& chr(34) ^& " prompt --continue", 0, False
>> "%HIDDEN_VBS%" echo Set WshShell = Nothing

REM --- 6. Desktop + Start Menu shortcuts ---
echo [6/6] Creating desktop and Start Menu shortcuts...

REM Desktop shortcut #1: interactive console (visible window)
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

REM Desktop shortcut #2: background (hidden, survives close)
powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%BG_SHORTCUT%'); ^
   $s.TargetPath = 'wscript.exe'; ^
   $s.Arguments = '\"//B\" \"%HIDDEN_VBS%\"'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.IconLocation = '%INSTALL_DIR%\rust\target\release\claw.exe,0'; ^
   $s.Description = 'Claw Code - runs hidden in background, survives close'; ^
   $s.WindowStyle = 7; ^
   $s.Save()"

REM Start Menu shortcut (same as #1)
powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; ^
   $s = $ws.CreateShortcut('%START_SHORTCUT%'); ^
   $s.TargetPath = 'cmd.exe'; ^
   $s.Arguments = '/k \"\"%WRAPPER%\"\"'; ^
   $s.WorkingDirectory = '%INSTALL_DIR%'; ^
   $s.IconLocation = '%INSTALL_DIR%\rust\target\release\claw.exe,0'; ^
   $s.Description = 'Claw Code - AI coding agent (Bitdeer + NVIDIA NIM)'; ^
   $s.WindowStyle = 1; ^
   $s.Save()"

popd

echo.
echo ==========================================================
echo   Done! Claw Code is ready.
echo ==========================================================
echo.
echo   Desktop shortcuts created:
echo     %SHORTCUT%
echo     %BG_SHORTCUT%
echo.
echo   Install dir:  %INSTALL_DIR%
echo.
echo   How to use:
echo     Double-click "Claw Code" on your desktop for an interactive session.
echo     Double-click "Claw Code (Background)" to run detached/hidden.
echo.
echo   From any cmd:
echo     "%WRAPPER%" prompt "hello"
echo     "%WRAPPER%" --model "nvidia/meta/llama-3.1-405b-instruct" prompt "hi"
echo.
echo   Smoke test providers:
echo     "%INSTALL_DIR%\scripts\test-providers.cmd"
echo.
echo   Re-configure providers later:
echo     "%INSTALL_DIR%\scripts\setup-providers.cmd"
echo.
endlocal
