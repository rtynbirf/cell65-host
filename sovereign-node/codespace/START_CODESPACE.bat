@echo off
rem CELL-65 :: start codespace supervisor (create + bootstrap + tunnel + watchdog)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp065-codespace.ps1" %*
pause
