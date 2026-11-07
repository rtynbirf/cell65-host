@echo off
rem CELL-65 entry point (dispatcher = the 65th cell)
setlocal
set "DIR=%~dp0"
if not exist "%DIR%65.ps1" (
  echo [CELL-65] 65.ps1 not found next to 65.cmd
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%65.ps1" %*
set "RC=%ERRORLEVEL%"
endlocal
exit /b %RC%
