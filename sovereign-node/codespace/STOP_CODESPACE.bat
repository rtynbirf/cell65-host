@echo off
rem CELL-65 :: stop codespace (kill tunnels + stop codespace, hours stop burning)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp065-codespace.ps1" -Stop %*
pause
