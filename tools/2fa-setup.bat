@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"
title 2FA-автомат GitHub — ноль сторонних

echo.
echo  ================================================
echo   2FA-АВТОМАТ GITHUB  —  totp.ps1, без сторонних
echo  ================================================
echo.

if exist totp.ps1 goto :got

echo  [1/5] Достаю генератор totp.ps1 из cell65-host...
curl.exe -fsSL -o totp.ps1 "https://raw.githubusercontent.com/rtynbirf/cell65-host/main/tools/totp.ps1" 2>nul
if exist totp.ps1 goto :got
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest 'https://raw.githubusercontent.com/rtynbirf/cell65-host/main/tools/totp.ps1' -OutFile 'totp.ps1'" >nul 2>&1
if exist totp.ps1 goto :got

echo.
echo  raw не отдал файл: репо в приватном режиме, анонимам 404.
echo  Ты залогинен в GitHub, поэтому файл увидишь в браузере.
echo  Батник сейчас откроет страницу файла. На ней:
echo    кнопка Raw, затем Ctrl+S, сохранить как totp.ps1 В ЭТУ ПАПКУ.
echo  Как только файл появится — батник продолжит САМ.
echo  Если totp.ps1 уже скачан в другое место — просто положи его
echo  рядом с этим батником и запусти батник заново.
echo.
pause
start "" "https://github.com/rtynbirf/cell65-host/blob/main/tools/totp.ps1"
:waitfile
if exist totp.ps1 goto :got
timeout /t 3 /nobreak >nul
goto :waitfile

:got
for %%A in (totp.ps1) do set TSIZE=%%~zA
if %TSIZE% LSS 1000 (
    echo  ОШИБКА: totp.ps1 подозрительно мал. Удали его и запусти батник заново.
    pause
    exit /b 1
)
echo  Готово: totp.ps1 на месте.
echo.

if exist totp.seed goto :code

echo  [2/5] Открываю страницу настройки 2FA в браузере...
start "" "https://github.com/settings/security"
echo.
echo  ДЕЛАЙ ПО СПИСКУ — 5 тычков в браузере:
echo   1. Войди в GitHub своим паролем.
echo   2. Нажми Enable two-factor authentication, пароль ещё раз.
echo   3. Выбери Authenticator app, жми Continue.
echo   4. На экране с картинкой-QR нажми ссылку ПОД ней:
echo      enter this text code instead
echo   5. Скопируй показанную строку-ключ.
echo.

powershell -NoProfile -Command "$k = Read-Host '[3/5] Вставь сюда строку-ключ и нажми Enter'; Set-Content -Path 'totp.seed' -Value $k -Encoding ASCII"
if errorlevel 1 (
    echo  ОШИБКА: сид не записан, запусти батник снова.
    pause
    exit /b 1
)
icacls totp.seed /inheritance:r /grant:r "%USERNAME%:F" >nul 2>&1
echo  Сид сохранён локально: totp.seed. НЕ коммитить, НЕ слать.
echo.

:code
echo  [4/5] Генерирую код...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0totp.ps1" -SeedFile "%~dp0totp.seed"
echo.
echo  [5/5] Вставь 6 цифр в окно GitHub и жми Continue.
echo.
echo  ДАЛЬШЕ ОБЯЗАТЕЛЬНО:
echo   - GitHub покажет 10 кодов восстановления: жми Download.
echo   - Файл кодов: одна копия на флешку, вторая в эту папку.
echo   - НЕ в репозиторий, НЕ в чат.
echo   - Каждый вход в GitHub: запускай этот батник — покажет свежие цифры.
echo   - Перевыпустить ключ: удали totp.seed и запусти батник заново.
echo.
pause
