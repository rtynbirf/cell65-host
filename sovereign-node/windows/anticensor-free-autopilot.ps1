# ==============================================================================
#  ANTICENSOR FREE AUTOPILOT v1.3 — бесплатный маршрут, настраивает всё сам
#  ЧЕЛЛОГ v1.3 (лог Хозяина 2026-10-31: встроенные мосты у провайдера добиты —
#  meek доходит до 20% и канал умирает, snowflake режется наголову):
#   - Psiphon теперь ПЕРВЫЙ в цепочке PAC: 1080 -> 8080 -> 9050 -> 9150 -> DIRECT,
#     чтобы мёртвый tor не тормозил каждую страницу.
#   - если tor не подключился — скрипт сам глушит свой tor.exe, чтобы браузер
#     не вис на мёртвом порту (ярлык автозапуска остаётся).
#   - в кандидаты транспортов добавлен lyrebird.exe: в новых Tor Browser
#     obfs4proxy переименован в lyrebird — без этого webtunnel-мосты из
#     bridges.txt были бы пропущены.
#  ЧЕЛЛОГ v1.2:
#   - мосты прописываются теперь и САМОМУ Tor Browser (firefox.exe из коробки):
#     его torrc чистится от старых Bridge/ClientTransportPlugin/UseBridges и
#     получает рабочие мосты + транспорты с АБСОЛЮТНЫМИ путями; исходный
#     torrc сохраняется рядом как torrc.bak. Браузер открыт — перезапусти его.
#   - при 100% подключения скрипт сам открывает Tor Browser (firefox.exe).
#  ЧЕЛЛОГ v1.1 (почему в v1.0 tor умирал с пустым логом):
#   - ГЛАВНЫЙ ФИКС: транспорт meek_lite в коробке обслуживает obfs4proxy.exe.
#     Файла meek-client.exe в современных Tor Browser НЕТ — из-за этого мост
#     meek выкидывался, tor оставался с нулём мостов и молча умирал.
#   - Строка "ClientTransportPlugin meek_lite,webtunnel" (через запятую) теперь
#     разбирается на отдельные транспорты.
#   - Заводские мосты вшиты как резерв: meek-azure + 2 snowflake.
#   - Мосты без найденного транспорта отсеиваются ДО старта — tor не падает.
#   - tor.exe запускается с перехватом stderr/stdout: при провале вердикт
#     печатает последние строки логов и код выхода (видно ПОЧЕМУ умер).
#   - Если tor умер сразу — выход сразу, а не ожидание 150 секунд.
#   - bridges.txt теперь тоже получает транспортные строки для своих мостов.
#   - Цепочка PAC: 9050 (автопилот) -> 9150 (Tor Browser) -> Psiphon -> DIRECT.
#  Одним запуском:
#   [1] находит твой Tor Browser (портативный, ищет по дискам)
#   [2] рабочая папка C:\ProgramData\AnticensorTor
#   [3] мосты: bridges.txt -> коробка Tor Browser -> заводской резерв
#   [4] torrc + скрытый tor.exe на 127.0.0.1:9050 (отдельно от браузера)
#   [5] ждёт Bootstrapped 100%, показывает прогресс
#   [6] свежий PAC с GitHub + цепочка движков, системный PAC включается
#   [7] автозапуск при входе в Windows + вердикт с логами
#  Идемпотентен: перезапуск в любой момент обновит мосты и переподнимет tor.
#  ФОЛБЭК (если meek у провайдера не едет): строки мостов из Telegram
#  @getbridgesbot (/webtunnel) вставить в bridges.txt в рабочей папке и
#  запустить скрипт снова. Скрипт ничего не спрашивает и пароли не читает.
# ==============================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RAW_PAC = 'https://raw.githubusercontent.com/rtynbirf/cell65-host/main/sovereign-node/pac/anticensor.pac'
$CHAIN   = "var PAC_PROXY = 'SOCKS5 127.0.0.1:1080; PROXY 127.0.0.1:8080; SOCKS5 127.0.0.1:9050; SOCKS5 127.0.0.1:9150; DIRECT';"
$ISReg   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function Say($s) { Write-Host $s }
function SayTail($path, $n) {
  if (Test-Path $path) {
    $t = @(Get-Content $path -Tail $n -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($t.Count -gt 0) { foreach ($l in $t) { Say ('    ' + $l) } }
    else { Say '    (пусто)' }
  } else { Say '    (файла нет)' }
}
function Test-PortListen([int]$port) {
  try { return ($null -ne (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) }
  catch { return $false }
}

# --- WinINET refresh без перезагрузки ---
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WIR {
  [DllImport("wininet.dll", SetLastError=true)]
  public static extern bool InternetSetOption(IntPtr h, int opt, IntPtr buf, int len);
  public static void Refresh() {
    InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
    InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
  }
}
'@
function Flush-Proxy { try { [WIR]::Refresh() } catch {} }

# --- [1] Найти Tor Browser ---
Say '[1/7] Ищу Tor Browser...'
$torExe = $null; $tbRoot = $null
$cands = New-Object System.Collections.Generic.List[string]
[void]$cands.Add('D:\PortableApps\Tor Browser\Tor Browser')
[void]$cands.Add('D:\PortableApps\Tor Browser')
[void]$cands.Add("$env:ProgramFiles\Tor Browser")
[void]$cands.Add("${env:ProgramFiles(x86)}\Tor Browser")
foreach ($d in @('D:\', "$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads")) {
  try {
    Get-ChildItem -Path $d -Directory -Recurse -Depth 3 -Filter 'Tor Browser' -ErrorAction SilentlyContinue |
      ForEach-Object { [void]$cands.Add($_.FullName) }
  } catch {}
}
foreach ($c in $cands) {
  $p = Join-Path $c 'Browser\TorBrowser\Tor\tor.exe'
  if (Test-Path $p) { $torExe = $p; $tbRoot = $c; break }
}
if (-not $torExe) {
  Say 'ПРОВАЛ: tor.exe от Tor Browser не найден. Проверь путь установки и запусти скрипт снова.'
  Say ('Ожидал внутри: Browser\TorBrowser\Tor\tor.exe')
  exit 1
}
$ptDir     = Join-Path $tbRoot 'Browser\TorBrowser\Tor\PluggableTransports'
$defTorrc  = Join-Path $tbRoot 'Browser\TorBrowser\Data\Tor\torrc-defaults'
$userTorrc = Join-Path $tbRoot 'Browser\TorBrowser\Data\Tor\torrc'
Say ("  Tor Browser: " + $tbRoot)
Say ("  транспорты:  " + $ptDir)

# --- [2] Рабочая папка ---
Say '[2/7] Рабочая папка...'
$work = Join-Path $env:ProgramData 'AnticensorTor'
try { [void](New-Item -ItemType Directory -Path $work -Force) } catch {
  $work = Join-Path $env:LOCALAPPDATA 'AnticensorTor'
  [void](New-Item -ItemType Directory -Path $work -Force)
}
$torrc      = Join-Path $work 'torrc'
$torLog     = Join-Path $work 'tor.log'
$errLog     = Join-Path $work 'tor-stderr.log'
$outLog     = Join-Path $work 'tor-stdout.log'
$bridgesTxt = Join-Path $work 'bridges.txt'
$dataDir    = Join-Path $work 'data'
$pacFile    = Join-Path $work 'anticensor-free.pac'
Say ("  " + $work)

# --- [3] Мосты: bridges.txt (ручные) -> коробка -> заводской резерв ---
Say '[3/7] Собираю мосты...'
$bridgeLines = @()
if (Test-Path $bridgesTxt) {
  $manual = @(Get-Content $bridgesTxt -ErrorAction SilentlyContinue |
    Where-Object { $_.Trim() -and ($_ -notmatch '^\s*#') } |
    ForEach-Object { ($_.Trim() -replace '^Bridge\s+', '') })
  if ($manual.Count -gt 0) {
    $bridgeLines += $manual
    Say ('  мосты из bridges.txt: ' + $manual.Count)
  }
}
if ($bridgeLines.Count -eq 0) {
  foreach ($src in @($userTorrc, $defTorrc)) {
    if (-not (Test-Path $src)) { continue }
    foreach ($l in (Get-Content $src -ErrorAction SilentlyContinue)) {
      if ($l -match '^\s*Bridge\s+\S+') {
        $b = ($l.Trim() -replace '^Bridge\s+', '')
        if ($bridgeLines -notcontains $b) { $bridgeLines += $b }
      }
    }
  }
  if ($bridgeLines.Count -gt 0) { Say ('  мосты из коробки Tor Browser: ' + $bridgeLines.Count) }
}
if ($bridgeLines.Count -eq 0) {
  $bridgeLines += 'meek_lite 192.0.2.2:2 97700CC4143A3AF18C6515D203D2637C498D06E5 url=https://meek.azureedge.net/ front=ajax.aspnetcdn.com'
  $bridgeLines += 'snowflake 192.0.2.4:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=socket.cdn77.org,ajax.aspnetcdn.com ice=stun:stun.l.google.com:19302'
  $bridgeLines += 'snowflake 192.0.2.5:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=socket.cdn77.org,ajax.aspnetcdn.com ice=stun:stun.l.google.com:19302'
  Say ('  коробка мостов не отдала — вшиты заводские: ' + $bridgeLines.Count)
}
# дедуп по отпечатку (40 hex) или по всей строке
$seen = @{}
$uniq = @()
foreach ($b in $bridgeLines) {
  $key = ''
  foreach ($tok in ($b -split '\s+')) { if ($tok -match '^[0-9A-Fa-f]{40}$') { $key = $tok.ToUpper(); break } }
  if (-not $key) { $key = $b }
  if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $uniq += $b }
}
$bridgeLines = $uniq

# транспорты, на которые ссылаются мосты
$needPt = @()
foreach ($b in $bridgeLines) { $needPt += (($b -split '\s+')[0]) }
$needPt = @($needPt | Select-Object -Unique)

# Кандидаты на транспорт: meek_lite/webtunnel/obfs4 в коробке обслуживают
# obfs4proxy.exe (старое имя) и lyrebird.exe (новое имя, TB 13+); snowflake — свой клиент.
$ptCand = @{
  'meek_lite' = @('obfs4proxy.exe', 'lyrebird.exe', 'meek-client.exe')
  'meek'      = @('meek-client.exe', 'lyrebird.exe', 'obfs4proxy.exe')
  'obfs4'     = @('obfs4proxy.exe', 'lyrebird.exe')
  'snowflake' = @('snowflake-client.exe')
  'webtunnel' = @('obfs4proxy.exe', 'lyrebird.exe', 'webtunnel-client.exe')
}
$pluginByT = @{}
# (i) готовые строки из коробки (torrc + torrc-defaults), в т.ч. через запятую
foreach ($src in @($userTorrc, $defTorrc)) {
  if (-not (Test-Path $src)) { continue }
  foreach ($l in (Get-Content $src -ErrorAction SilentlyContinue)) {
    if ($l -match '^\s*ClientTransportPlugin\s+(\S+)\s+exec\s+(.+?)\s*$') {
      $exe = $Matches[2].Trim().Trim('"').Trim("'")
      if (-not (Test-Path $exe)) {
        $c2 = Join-Path $ptDir (Split-Path $exe -Leaf)
        if (Test-Path $c2) { $exe = $c2 }
      }
      foreach ($t in ($Matches[1] -split ',')) {
        $t = $t.Trim()
        if ($t -and (Test-Path $exe) -and (-not $pluginByT.ContainsKey($t))) { $pluginByT[$t] = $exe }
      }
    }
  }
}
# (ii) добор по имени файла из коробки
foreach ($t in $needPt) {
  if ($pluginByT.ContainsKey($t)) { continue }
  if (-not $ptCand.ContainsKey($t)) { continue }
  foreach ($fn in $ptCand[$t]) {
    $exe = Join-Path $ptDir $fn
    if (Test-Path $exe) { $pluginByT[$t] = $exe; break }
  }
}
# (iii) мосты без транспорта отсеиваем ДО старта, иначе tor умирает молча
$usable = @()
foreach ($b in $bridgeLines) {
  $t = ($b -split '\s+')[0]
  if ($pluginByT.ContainsKey($t)) { $usable += $b }
  else { Say ('  ВНИМАНИЕ: транспорт ' + $t + ' не найден в коробке — мост этого типа пропущен.') }
}
$bridgeLines = $usable
$needPt = @()
foreach ($b in $bridgeLines) { $needPt += (($b -split '\s+')[0]) }
$needPt = @($needPt | Select-Object -Unique)
if ($bridgeLines.Count -gt 0) {
  Say ('  мостов к использованию: ' + $bridgeLines.Count)
  foreach ($t in $needPt) { Say ('    транспорт ' + $t + ' -> ' + (Split-Path $pluginByT[$t] -Leaf)) }
} else {
  Say '  РАБОЧИХ МОСТОВ НЕТ — tor будет поднят напрямую (провайдер может резать).'
}

# --- [4] torrc + старт скрытого tor.exe ---
Say '[4/7] Пишу конфиги и поднимаю скрытый tor.exe (порт 9050)...'
$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add('SocksPort 127.0.0.1:9050')
[void]$lines.Add(('DataDirectory "' + $dataDir + '"'))
[void]$lines.Add(('Log notice file "' + $torLog + '"'))
foreach ($t in $needPt) {
  [void]$lines.Add(('ClientTransportPlugin ' + $t + ' exec "' + $pluginByT[$t] + '"'))
}
if ($bridgeLines.Count -gt 0) { [void]$lines.Add('UseBridges 1') }
foreach ($l in $bridgeLines) { [void]$lines.Add(('Bridge ' + $l)) }
[IO.File]::WriteAllLines($torrc, $lines)
# пустой defaults: чтобы ничего из коробки/системы не вмешивалось — весь контроль в нашем torrc
$blankDefaults = Join-Path $work 'blank-defaults.torrc'
[IO.File]::WriteAllText($blankDefaults, "# пусто: полный контроль в torrc`r`n")

# --- те же мосты — и самому браузеру из коробки (firefox.exe) ---
$ffExe = Join-Path $tbRoot 'Browser\firefox.exe'
try {
  $boxRunning = $false
  Get-CimInstance Win32_Process -Filter "Name = 'firefox.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like ('*' + $tbRoot + '*') } |
    ForEach-Object { $boxRunning = $true }
  $kept = @()
  if (Test-Path $userTorrc) {
    if (-not (Test-Path ($userTorrc + '.bak'))) { try { Copy-Item $userTorrc ($userTorrc + '.bak') -ErrorAction Stop } catch {} }
    $kept = @(Get-Content $userTorrc -ErrorAction SilentlyContinue | Where-Object {
      ($_ -notmatch '^\s*Bridge\s+') -and ($_ -notmatch '^\s*ClientTransportPlugin\s+') -and ($_ -notmatch '^\s*UseBridges\s+')
    })
  }
  $bl = New-Object System.Collections.Generic.List[string]
  foreach ($l in $kept) { [void]$bl.Add($l) }
  foreach ($t in $needPt) { [void]$bl.Add(('ClientTransportPlugin ' + $t + ' exec "' + $pluginByT[$t] + '"')) }
  if ($bridgeLines.Count -gt 0) { [void]$bl.Add('UseBridges 1') } else { [void]$bl.Add('UseBridges 0') }
  foreach ($l in $bridgeLines) { [void]$bl.Add(('Bridge ' + $l)) }
  [IO.File]::WriteAllLines($userTorrc, $bl)
  Say ('  мосты прописаны и браузеру из коробки (firefox.exe): ' + $userTorrc)
  if ($boxRunning) { Say '  ВНИМАНИЕ: Tor Browser сейчас открыт — ПЕРЕЗАПУСТИ его, чтобы он взял мосты.' }
} catch {
  Say ('  Не смог прописать мосты браузеру (не критично): ' + $_.Exception.Message)
}

Get-CimInstance Win32_Process -Filter "Name = 'tor.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -like '*AnticensorTor*' } |
  ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
Start-Sleep -Seconds 1
Remove-Item $torLog, $errLog, $outLog -ErrorAction SilentlyContinue

$proc = $null
try {
  $proc = Start-Process -FilePath $torExe -ArgumentList @('--defaults-torrc', ('"' + $blankDefaults + '"'), '-f', ('"' + $torrc + '"')) -WorkingDirectory (Split-Path $torExe) -WindowStyle Hidden -RedirectStandardError $errLog -RedirectStandardOutput $outLog -PassThru
} catch {
  Say ('  ОШИБКА ЗАПУСКА tor.exe: ' + $_.Exception.Message)
}
try {
  if (-not (Get-NetFirewallRule -DisplayName 'AnticensorTor-tor' -ErrorAction SilentlyContinue)) {
    [void](New-NetFirewallRule -DisplayName 'AnticensorTor-tor' -Direction Outbound -Program $torExe -Action Allow -ErrorAction Stop)
    Say '  правило брандмауэра добавлено.'
  }
} catch { Say '  (нет прав на правило брандмауэра — если Windows спросит про tor.exe, жми РАЗРЕШИТЬ)' }

# --- [5] Жду подключения (до 150 секунд; если процесс умер — выходим сразу) ---
Say '[5/7] Жду подключения к сети Tor (до 150 с)...'
$deadline  = (Get-Date).AddSeconds(150)
$lastPct   = -1
$lastShown = -1
$done      = $false
$exited    = $false
$listening = $false
if ($proc) {
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 4
    if ($proc.HasExited) { $exited = $true; break }
    if (-not $listening) { $listening = Test-PortListen 9050 }
    if (Test-Path $torLog) {
      foreach ($l in (Get-Content $torLog -Tail 15 -ErrorAction SilentlyContinue)) {
        if ($l -match 'Bootstrapped (\d+)%') { $lastPct = [int]$Matches[1] }
        if ($l -match 'Bootstrapped 100%') { $done = $true }
      }
    }
    if ($done) { break }
    if ($lastPct -ne $lastShown -and $lastPct -ge 0) { Say ('  прогресс: ' + $lastPct + '%'); $lastShown = $lastPct }
  }
}
# не подключился — глушим свой tor, чтобы браузер не вис на мёртвом порту
if (-not $done -and $proc -and -not $proc.HasExited) {
  try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop; $listening = $false
        Say '  скрытый tor остановлен (не подключился) — браузер не будет висеть на мёртвом порту.' } catch {}
}

# --- [6] PAC: качаю свежий, вшиваю цепочку, включаю системно ---
Say '[6/7] PAC...'
$pacText = $null
try {
  $wc = New-Object System.Net.WebClient
  $pacText = [Text.Encoding]::UTF8.GetString($wc.DownloadData($RAW_PAC))
  Say ("  PAC скачан с GitHub: " + $pacText.Length + " символов.")
} catch { Say ("  GitHub не отдал PAC: " + $_.Exception.Message) }
if ($pacText -and $pacText -match 'FindProxyForURL') {
  $pat = "var PAC_PROXY = '[^']*';"
  $cnt = [regex]::Matches($pacText, $pat).Count
  if ($cnt -eq 1) {
    $patched = [regex]::Replace($pacText, $pat, $CHAIN)
    [IO.File]::WriteAllBytes($pacFile, [Text.Encoding]::UTF8.GetBytes($patched))
    Say ("  PAC собран: " + $pacFile)
  } else {
    Say ("  ОШИБКА: строк PAC_PROXY в файле " + $cnt + " — PAC не собираю.")
  }
} elseif (Test-Path $pacFile) {
  Say '  GitHub недоступен — использую уже собранный PAC.'
} else {
  Say '  PAC не собран: скачай anticensor-free.pac из чата и положи в рабочую папку.'
}
if (Test-Path $pacFile) {
  $pacUrl = 'file:///' + ($pacFile -replace '\\', '/')
  Remove-ItemProperty -Path $ISReg -Name AutoConfigURL -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $ISReg -Name AutoConfigURL -Value $pacUrl -Type String
  Flush-Proxy
  $now = (Get-ItemProperty $ISReg).AutoConfigURL
  if ($now -eq $pacUrl) { Say '  СИСТЕМНЫЙ PAC ВКЛЮЧЁН.' } else { Say '  Не подтвердилась запись в реестр — проверь Параметры -> Сеть -> Прокси.' }
}

# --- [7] Автозапуск при входе в Windows ---
Say '[7/7] Автозапуск...'
try {
  $ws  = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\AnticensorTor.lnk'))
  $lnk.TargetPath      = $torExe
  $lnk.Arguments       = ('--defaults-torrc "' + $blankDefaults + '" -f "' + $torrc + '"')
  $lnk.WorkingDirectory = Split-Path $torExe
  $lnk.WindowStyle     = 7
  $lnk.Save()
  Say '  Ярлык в автозагрузке создан (tor будет подниматься сам при входе).'
} catch { Say ("  Автозапуск не создался: " + $_.Exception.Message) }

# --- ВЕРДИКТ ---
Say ''
Say '================ ВЕРДИКТ ================'
if ($done) {
  Say 'TOR ПОДКЛЮЧЁН (100%). Маршрут: заблокированные домены -> Tor -> интернет, RU -> напрямую.'
  if (Test-Path $ffExe) {
    try { Start-Process -FilePath $ffExe ; Say '  Tor Browser (firefox.exe) открыт — проверяй 2ip.ru и заблокированные сайты.' } catch {}
  }
} elseif ($exited) {
  $code = ''
  try { $code = $proc.ExitCode } catch {}
  Say ('TOR.EXE ЗАВЕРШИЛСЯ САМ (код выхода: ' + $code + '). Последние строки логов:')
  Say ('  ' + $torLog + ':')
  SayTail $torLog 10
  Say ('  ' + $errLog + ':')
  SayTail $errLog 10
  Say '  Частые причины: антивирус убил tor.exe (добавь Tor Browser в исключения),'
  Say '  либо ошибка в конфиге — она видна в строках выше.'
} elseif ($lastPct -ge 0) {
  Say ('TOR ЗАСТРЯЛ НА ' + $lastPct + '% — провайдер добил и эти мосты (встроенные в РФ сейчас мертвы). Два пути:')
  Say '  ПУТЬ 1 (самый быстрый, без мостов) — Psiphon:'
  Say '    скачай Psiphon 3 для Windows (psiphon3.com), запусти, в настройках ВЫКЛЮЧИ «Режим VPN»'
  Say '    (нужен режим ПРОКСИ) — он поднимет 127.0.0.1:8080/1080, PAC подхватит его сам.'
  Say '  ПУТЬ 2 (чинит Tor по-настоящему) — личные мосты webtunnel:'
  Say '    1) Telegram @getbridgesbot -> команда /webtunnel (их нет в дефолтных списках — цензор не знает, что резать).'
  Say '    2) Скопируй строки мостов из ответа бота (каждая строка целиком).'
  Say ('    3) Вставь их в файл ' + $bridgesTxt + ' (блокнот открою сейчас).')
  Say '    4) Запусти этот скрипт снова — он переподнимет tor с новыми мостами.'
  try { if (-not (Test-Path $bridgesTxt)) { [IO.File]::WriteAllText($bridgesTxt, "# вставь строки мостов ниже, по одной на строке`r`n") } ; Start-Process notepad $bridgesTxt } catch {}
} elseif ($listening) {
  Say 'TOR ЗАПУЩЕН И СЛУШАЕТ 9050, но к сети не подключился (прогресса в логе нет). Лог:'
  SayTail $torLog 10
} else {
  Say 'TOR НЕ ОТВЕЧАЕТ. Последние строки логов:'
  Say ('  ' + $torLog + ':')
  SayTail $torLog 10
  Say ('  ' + $errLog + ':')
  SayTail $errLog 10
  Say '  Частая причина: антивирус или брандмауэр не пустил tor.exe — добавь в исключения / РАЗРЕШИТЬ.'
  Say '  Если процесс так и не жив: ПУТЬ 1 — Psiphon (psiphon3.com, режим прокси), ПУТЬ 2 — мосты webtunnel в bridges.txt.'
}
Say ''
Say 'Проверки в браузере:'
Say '  1) 2ip.ru — показывает ТВОЙ домашний IP (правильно: RU напрямую).'
Say '  2) Заблокированный сайт — открывается (пошёл через Tor).'
Say '  3) Расширение «Антицензор» в Chrome — ВЫКЛЮЧИТЬ, чтобы не перекрывало PAC.'
Say 'ОТКАТ: удалить ярлык Startup\AnticensorTor.lnk; Параметры -> Сеть -> Прокси -> сценарий -> ВЫКЛ.'
Say 'Свежесть PAC: перезапусти этот скрипт раз в месяц — пересоберёт список с GitHub.'
