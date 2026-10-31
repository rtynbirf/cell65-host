@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"
title 2FA-автомат GitHub v2 — ноль сторонних

echo.
echo  ================================================
echo   2FA-АВТОМАТ GITHUB v2  —  totp.ps1, без сторонних
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

if not exist totp.seed goto :fresh

rem --- v2: сид есть — проверяем, читается ли (урок TH-GH-08) ---
powershell -NoProfile -Command "try { $null = Get-Content 'totp.seed' -Raw -ErrorAction Stop; exit 0 } catch { exit 3 }"
if not errorlevel 3 goto :code
echo  Файл totp.seed есть, но НЕ ЧИТАЕТСЯ — чиню права...
icacls totp.seed /reset >nul 2>&1
powershell -NoProfile -Command "try { $null = Get-Content 'totp.seed' -Raw -ErrorAction Stop; exit 0 } catch { exit 3 }"
if not errorlevel 3 goto :code
echo  Права не вернулись — удаляю старый сид, настроим ключ заново.
del /f /q totp.seed >nul 2>&1
if exist totp.seed (
    echo  НЕ УДАЛОСЬ удалить totp.seed. Удали его в Проводнике руками,
    echo  затем запусти батник заново.
    pause
    exit /b 1
)

:fresh
echo  [2/5] Открываю страницу настройки 2FA в браузере...
start "" "https://github.com/settings/security"
echo.
echo  ДЕЛАЙ ПО СПИСКУ — 5 тычков в браузере:
echo   1. Войди в GitHub своим паролем.
echo   2. Нажми Enable two-factor authentication, пароль ещё раз.
echo   3. Выбери Authenticator app, жми Continue.
echo   4. На экране с картинкой-QR найди строку:
echo      Unable to scan? You can use the ... to manually configure...
echo      и нажми в ней ПОДСВЕЧЕННОЕ СЛОВО-ССЫЛКУ (setup key).
echo   5. Скопируй показанную строку-ключ (буквы A-Z и цифры 2-7).
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; while($true){ $sec=Read-Host '[3/5] Вставь строку-ключ (ввод скрыт звёздочками) и жми Enter' -AsSecureString; $plain=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)); $clean=($plain.ToUpper() -replace '[^A-Z2-7]',''); if($clean.Length -lt 16 -or $clean.Length -gt 64){ Write-Host '  ПОХОЖЕ, ЧТО СКОПИРОВАЛОСЬ НЕ ТО: в строке-ключе 16-64 символов (буквы A-Z, цифры 2-7). Выдели на странице GitHub ТОЛЬКО строку-ключ и вставь ещё раз.' -ForegroundColor Yellow } else { if($clean.Length -ne 16 -and $clean.Length -ne 32){ Write-Host ('  ВНИМАНИЕ: нестандартная длина ключа ({0}) — если GitHub отвергнет цифры, перевыпусти ключ.' -f $clean.Length) -ForegroundColor Yellow }; break } }; Set-Content -Path 'totp.seed' -Value $clean -Encoding ASCII; $ErrorActionPreference='Continue'; $null=icacls 'totp.seed' /inheritance:r /grant:r ('*{0}:F' -f $sid) 2>&1; $ErrorActionPreference='Stop'; try { $null=Get-Content 'totp.seed' -Raw -ErrorAction Stop; Write-Host '  Сид сохранён и читается. НЕ коммитить, НЕ слать в чат.' } catch { $ErrorActionPreference='Continue'; $null=icacls 'totp.seed' /reset 2>&1; $ErrorActionPreference='Stop'; try { $null=Get-Content 'totp.seed' -Raw -ErrorAction Stop; Write-Host '  Сид сохранён, права стандартные.' } catch { Write-Host '  ОШИБКА: totp.seed не читается даже после сброса прав.' -ForegroundColor Red; Write-Host '  Удали totp.seed в Проводнике и запусти батник заново.' -ForegroundColor Red; exit 9 } }; Write-Host ('  Длина ключа: {0} символов.' -f $clean.Length)"
if errorlevel 1 (
    echo.
    echo  Сид не записан. Удали totp.seed, если он есть, и запусти батник заново.
    pause
    exit /b 1
)
echo.

:code
echo  [4/5] Генерирую код...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0totp.ps1" -SeedFile "%~dp0totp.seed"
if errorlevel 1 (
    echo.
    echo  Генератор споткнулся: обычно это права на totp.seed или мусор в нём.
    echo  Лечение: удали totp.seed и запусти батник заново со свежим ключом.
)
echo.
echo  [5/5] Вставь 6 цифр в окно GitHub и жми Continue.
echo.
echo  ДАЛЬШЕ ОБЯЗАТЕЛЬНО:
echo   - GitHub покажет 10 кодов восстановления: жми Download.
echo   - Файл кодов: одна копия на флешку, вторая в эту папку.
echo   - НЕ в репозиторий, НЕ в чат.
echo   - Ключ вводится скрыто звёздочками — это норма, так и задумано.
echo   - Строку-ключ никогда не показывать в чате; 6 цифр не страшно.
echo   - Каждый вход в GitHub: запускай этот батник — покажет свежие цифры.
echo   - Перевыпустить ключ: удали totp.seed и запусти батник заново.
echo.
pause
