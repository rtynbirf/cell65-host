# ============================================================
# CELL-65 :: GitHub Codespace — подъем "сервера" и супервизор туннеля
# ------------------------------------------------------------
# Запуск (из папки, где лежит этот файл и codespace-bootstrap.sh):
#   powershell -ExecutionPolicy Bypass -File .\65-codespace.ps1
# Только настройка и проверка, без супервизора:
#   powershell -ExecutionPolicy Bypass -File .\65-codespace.ps1 -Once
# Останов (убить туннель и погасить codespace — часы тикать перестают):
#   powershell -ExecutionPolicy Bypass -File .\65-codespace.ps1 -Stop
#
# Что делает:
#   1) ставит gh CLI (winget), логинит (токен из %USERPROFILE%\cell65\gh_token.txt или браузер)
#   2) создает приватный репозиторий cell65-host + Codespace cell65-host (если нет)
#   3) заливает codespace-bootstrap.sh и запускает его (gost: HTTP 18080 + SOCKS5 18081)
#   4) держит SSH-туннель (белый IP не нужен):
#        127.0.0.1:19080 -> HTTP  внутри codespace
#        127.0.0.1:19081 -> SOCKS5 внутри codespace
#   5) сторож: туннель умер / codespace уснул — поднимает сам
#
# Апстрим для CELL-65 (gost на твоей машине):
#   socks5://127.0.0.1:19081
# ============================================================
param(
  [string]$DisplayName = "cell65-host",
  [string]$RepoName    = "cell65-host",
  [string]$TokenFile   = "$env:USERPROFILE\cell65\gh_token.txt",
  [int]$LocalHttp  = 19080,
  [int]$LocalSocks = 19081,
  [int]$RemoteHttp  = 18080,
  [int]$RemoteSocks = 18081,
  [int]$PingSec = 60,
  [switch]$Once,
  [switch]$Stop
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Dir = Join-Path $env:USERPROFILE "cell65"
$Log = Join-Path $Dir "codespace-tunnel.log"
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

function Log([string]$m) {
  $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  try { Add-Content -Path $Log -Value $line -Encoding UTF8 } catch {}
  Write-Host $line
}

function Test-Port([int]$port) {
  $c = New-Object Net.Sockets.TcpClient
  try { $c.Connect("127.0.0.1", $port); return $c.Connected }
  catch { return $false }
  finally { $c.Dispose() }
}

function Test-Auth {
  gh auth status > $null 2>&1
  return ($LASTEXITCODE -eq 0)
}

function Kill-OldTunnels {
  Get-CimInstance Win32_Process -Filter "Name='gh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match "19081" } |
    ForEach-Object {
      Log "убиваю старый туннель PID $($_.ProcessId)"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

# ---------------- РЕЖИМ -Stop ----------------
if ($Stop) {
  Kill-OldTunnels
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    if (Test-Auth) {
      $csF = gh cs list --json name,displayName,state 2>$null | ConvertFrom-Json
      $c = @($csF) | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
      if ($c) {
        gh cs stop -c $c.name > $null 2>&1
        Log "codespace $($c.name) погашен"
      } else {
        Log "codespace '$DisplayName' не найден — уснет сам по idle"
      }
    } else {
      Log "нет авторизации gh — codespace уснет сам по idle (30 мин)"
    }
  } else {
    Log "gh не установлен — codespace уснет сам по idle (30 мин)"
  }
  Log "STOP: туннели убиты, часы остановлены/остановятся"
  exit 0
}

# ---------------- 1. gh CLI ----------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Log "gh CLI не найден — ставлю через winget (1-2 мин)"
  winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements | Out-Null
  $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Log "FAIL: gh не появился — перезапусти консоль и скрипт"; exit 1 }
}
Log ("gh: " + ((gh --version) | Select-Object -First 1))

# ---------------- 2. логин ----------------
if (-not (Test-Auth)) {
  if (Test-Path $TokenFile) {
    Log "логин по токену из $TokenFile"
    ((Get-Content $TokenFile -Raw).Trim()) | gh auth login --with-token > $null 2>&1
  } else {
    Log "токен не найден ($TokenFile) — открою браузер для входа (один раз)"
    gh auth login -h github.com -p https -w
  }
  if (-not (Test-Auth)) { Log "FAIL: вход в GitHub не удался"; exit 1 }
}

# скоуп codespace
gh cs list --json name > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  Log "добавляю скоуп codespace (подтверди в браузере)"
  gh auth refresh -h github.com -s codespace
  gh cs list --json name > $null 2>&1
  if ($LASTEXITCODE -ne 0) { Log "FAIL: скоуп codespace не добавлен"; exit 1 }
}

$Owner = (gh api user --jq ".login")
if (-not $Owner) { Log "FAIL: не получил логин аккаунта"; exit 1 }
$Owner = "$Owner".Trim()
Log "аккаунт: $Owner"

# ---------------- 3. репозиторий ----------------
gh repo view "$Owner/$RepoName" > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  Log "создаю приватный репозиторий $RepoName"
  gh repo create $RepoName --private > $null 2>&1
}

# ---------------- 4. codespace ----------------
function Get-CS {
  $csF = gh cs list --json name,displayName,state 2>$null | ConvertFrom-Json
  return @($csF) | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
}

$cs = Get-CS
if (-not $cs) {
  Log "создаю Codespace '$DisplayName' (2 ядра / 8 ГБ ОЗУ / 32 ГБ диск)..."
  gh cs create -R "$Owner/$RepoName" -m basicLinux32gb -d $DisplayName --default-permissions > $null 2>&1
  if ($LASTEXITCODE -ne 0) {
    Log "машина basicLinux32gb не принялась — пробую дефолтную"
    gh cs create -R "$Owner/$RepoName" -d $DisplayName --default-permissions > $null 2>&1
  }
  Log "жду готовность (1-3 мин)..."
  $deadline = (Get-Date).AddSeconds(240)
  do {
    Start-Sleep 10
    $cs = Get-CS
    if ($cs) { Log ("  состояние: " + $cs.state) }
  } while ($cs -and $cs.state -notin @("Running","Starting","Shutdown","Stopped") -and (Get-Date) -lt $deadline)
  if (-not $cs) { Log "FAIL: codespace не создался"; exit 1 }
}
$script:CsName = $cs.name
Log "codespace: $script:CsName (состояние: $($cs.state))"

# ---------------- 5. bootstrap ----------------
$BootPath = Join-Path $PSScriptRoot "codespace-bootstrap.sh"
if (-not (Test-Path $BootPath)) { Log "FAIL: рядом нет codespace-bootstrap.sh"; exit 1 }
$script:BootB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content $BootPath -Raw)))

function Start-CS {
  $c = gh cs list --json name,state 2>$null | ConvertFrom-Json | Where-Object { $_.name -eq $script:CsName } | Select-Object -First 1
  if ($c -and $c.state -ne "Running" -and $c.state -ne "Starting") {
    Log "codespace $script:CsName спит ($($c.state)) — буджу (часы пошли)"
    gh api -X POST "user/codespaces/$script:CsName/start" > $null 2>&1
    Start-Sleep 15
  }
}

function Deploy-And-Run {
  Start-CS
  Log "заливаю и запускаю bootstrap (gost: HTTP $RemoteHttp + SOCKS5 $RemoteSocks)..."
  gh cs ssh -c $script:CsName -- "mkdir -p ~/c65 && echo $script:BootB64 | base64 -d > ~/c65/bootstrap.sh && bash ~/c65/bootstrap.sh"
  return ($LASTEXITCODE -eq 0)
}

function Start-Tunnel {
  $ghExe = (Get-Command gh).Source
  $sshArgs = @("cs","ssh","-c",$script:CsName,"--","-N",
    "-L","${LocalHttp}:127.0.0.1:${RemoteHttp}",
    "-L","${LocalSocks}:127.0.0.1:${RemoteSocks}")
  $p = Start-Process -FilePath $ghExe -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
  Log ("туннель: PID " + $p.Id + "  HTTP 127.0.0.1:" + $LocalHttp + "  SOCKS5 127.0.0.1:" + $LocalSocks)
  return $p
}

Kill-OldTunnels

$bootOk = $false
for ($i = 1; $i -le 3; $i++) {
  if (Deploy-And-Run) { $bootOk = $true; break }
  Log "попытка $i не прошла, жду 20 с"
  Start-Sleep 20
}
if (-not $bootOk) { Log "FAIL: bootstrap в codespace не отработал после 3 попыток"; exit 1 }

$tunnel = Start-Tunnel
Start-Sleep 6
$ok0 = Test-Port $LocalSocks
if ($ok0) {
  Log "ТУННЕЛЬ ЖИВОЙ: socks5://127.0.0.1:$LocalSocks  (это апстрим для CELL-65)"
} else {
  Log "туннель еще поднимается — сторож доложит"
}
if ($Once) {
  if ($ok0) { Log "ONCE-режим: готово, выхожу (супервизор не оставлен)"; exit 0 }
  exit 1
}

# ---------------- 6. супервизор ----------------
$sessionStart = Get-Date
$tick = 0
Log "супервизор работает. Останов: .\65-codespace.ps1 -Stop"
Log "расход часов: https://github.com/settings/billing (лимит 60 ч/мес)"
while ($true) {
  Start-Sleep -Seconds $PingSec
  $tick++
  if (-not (Test-Port $LocalSocks)) {
    Log "туннель умер — реанимация"
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue }
    if (Deploy-And-Run) { $tunnel = Start-Tunnel; Start-Sleep 6 }
    else { Log "bootstrap не прошел — повторю через минуту" }
    continue
  }
  if ($tick % 10 -eq 0) {
    gh cs ssh -c $script:CsName -- "echo keepalive" > $null 2>&1
    $mins = [int]((Get-Date) - $sessionStart).TotalMinutes
    Log "живой: $mins мин этого сеанса (keepalive отправлен)"
  }
}
