@echo off
REM setup-providers.cmd - Windows wrapper for the .sh setup script
setlocal
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
where bash >nul 2>&1
if errorlevel 1 (
  if exist "C:\Program Files\Git\bin\bash.exe" (
    set "PATH=C:\Program Files\Git\bin;%PATH%"
  ) else (
    echo X bash not found. Install Git for Windows.
    popd & exit /b 1
  )
)
bash scripts\setup-providers.sh
popd
endlocal
