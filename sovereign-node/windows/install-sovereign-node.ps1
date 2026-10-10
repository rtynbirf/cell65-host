# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — установка клиента на Windows 11
#  Правый клик -> "Выполнить с помощью PowerShell" (ОТ ИМЕНИ АДМИНИСТРАТОРА)
#  Или:  powershell -ExecutionPolicy Bypass -File install-sovereign-node.ps1
#
#  Что делает (идемпотентно, можно запускать повторно):
#    1. Читает node.env (единственный файл правды)
#    2. Ставит sing-box (один бинарь) в C:\Program Files\sovereign-node
#    3. Рендерит конфиг: лестница T1 Reality / T2 WS через Cloudflare / T3 Hysteria2
#       + раздельная маршрутизация (RU напрямую, всё остальное через лестницу)
#    4. Регистрирует службу Windows с автоперезапуском и стартует её (TUN-режим)
#  Если DOMAIN пуст — T2 не включается (включится после provision-edge.ps1).
# ============================================================
#Requires -RunAsAdministrator
param([switch]$RenderOnly)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Base  = "C:\Program Files\sovereign-node"
$Bin   = "$Base\bin"
$Data  = "C:\ProgramData\sovereign-node"
$Svc   = "SovereignNode"
$Root  = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- 1. node.env ----------
$envFile = Join-Path $Root "node.env"
if (-not (Test-Path $envFile)) { Write-Host "НЕТ node.env рядом со скриптом: $envFile" -ForegroundColor Red; exit 1 }
$V = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') { $V[$Matches[1]] = $Matches[2].Trim() }
}
if (-not $V["VPS_IP"]) {
  Write-Host "VPS_IP пуст в node.env.`nВпши IP своего VPS и запусти установку снова.`n(Без VPS некуда идти — это физика, а не прихоть.)" -ForegroundColor Yellow
  exit 1
}
$withT2 = [bool]$V["DOMAIN"]
Write-Host ("Узел: VPS={0}  домен={1}" -f $V["VPS_IP"], $(if($withT2){$V["DOMAIN"]}else{"(нет — T2 пропущен)"}))

# ---------- 2. sing-box ----------
New-Item -ItemType Directory -Force -Path $Bin, $Data | Out-Null
if (-not $RenderOnly) {
  if (-not (Test-Path "$Bin\sing-box.exe")) {
    Write-Host "Загрузка sing-box (последний релиз)..."
    $ver = $null
    try { $ver = (Invoke-RestMethod "https://api.github.com/repos/SagerNet/sing-box/releases/latest" -TimeoutSec 20).tag_name } catch {}
    if (-not $ver) {
      try {
        [xml]$feed = Invoke-RestMethod "https://github.com/SagerNet/sing-box/releases.atom" -TimeoutSec 20
        $ver = ($feed.feed.entry[0].id -replace '.*/v','')
      } catch {}
    }
    if (-not $ver) { Write-Host "GitHub недоступен. Проверь сеть или скачай релиз вручную." -ForegroundColor Red; exit 1 }
    $ver = $ver.TrimStart("v")
    $asset = "sing-box-$ver-windows-amd64.zip"
    $zip = Join-Path $env:TEMP $asset
    Invoke-WebRequest "https://github.com/SagerNet/sing-box/releases/download/v$ver/$asset" -OutFile $zip -TimeoutSec 300
    $tmp = Join-Path $env:TEMP "sbx_$ver"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive $zip $tmp -Force
    Copy-Item "$tmp\sing-box-$ver-windows-amd64\*" $Bin -Force
    Remove-Item $tmp, $zip -Force -ErrorAction SilentlyContinue
    Write-Host "sing-box v$ver установлен."
  } else { Write-Host "sing-box уже установлен — пропускаю загрузку." }
}

# ---------- 3. Конфиг ----------
$T2BLOCK = @'
    {
      "type": "vless",
      "tag": "T2-CF-WS",
      "server": "__DOMAIN__",
      "server_port": __XP__,
      "uuid": "__UUID__",
      "tls": {
        "enabled": true,
        "server_name": "__DOMAIN__",
        "utls": { "enabled": true, "fingerprint": "chrome" }
      },
      "transport": { "type": "ws", "path": "__T2PATH__" }
    },
'@

if ($withT2) { $ladder = @("T1-REALITY","T2-CF-WS","T3-HY2") } else { $ladder = @("T1-REALITY","T3-HY2") }
$ladderJson = ($ladder | ForEach-Object { "`"$_`"" }) -join ","

$cfg = @"
{
  "log": { "level": "warn", "timestamp": true, "output": "$($Data.Replace('\','\\'))\\singbox.log" },
  "experimental": {
    "cache_file": { "enabled": true, "path": "$($Data.Replace('\','\\'))\\cache.db", "store_rdrc": true },
    "clash_api": { "external_controller": "127.0.0.1:9090", "default_mode": "rule" }
  },
  "dns": {
    "servers": [
      { "type": "https", "tag": "dns-remote", "server": "8.8.8.8", "detour": "LADDER" },
      { "type": "udp", "tag": "dns-ru", "server": "77.88.8.8", "detour": "DIRECT" }
    ],
    "rules": [
      { "rule_set": ["geosite-ru"], "server": "dns-ru" }
    ],
    "final": "dns-remote",
    "strategy": "prefer_ipv4",
    "independent_cache": true
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
      "auto_route": true,
      "strict_route": true
    }
  ],
  "outbounds": [
    {
      "type": "urltest",
      "tag": "LADDER",
      "outbounds": [$ladderJson],
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 50
    },
    {
      "type": "vless",
      "tag": "T1-REALITY",
      "server": "__VPS_IP__",
      "server_port": __RP__,
      "uuid": "__UUID__",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "__SNI__",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": { "enabled": true, "public_key": "__RPUB__", "short_id": "__SID__" }
      }
    },
__T2_OR_EMPTY__
    {
      "type": "hysteria2",
      "tag": "T3-HY2",
      "server": "__VPS_IP__",
      "server_port": __HP__,
      "password": "__HPW__",
      "obfs": { "type": "salamander", "password": "__OBFS__" },
      "tls": { "enabled": true, "insecure": true, "server_name": "__SNI__" }
    },
    { "type": "direct", "tag": "DIRECT" }
  ],
  "route": {
    "rules": [
      { "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" },
      { "ip_is_private": true, "outbound": "DIRECT" },
      { "rule_set": ["geosite-ru"], "outbound": "DIRECT" },
      { "rule_set": ["geoip-ru"], "outbound": "DIRECT" }
    ],
    "rule_set": [
      { "type": "remote", "tag": "geosite-ru", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-ru.srs",
        "download_detour": "DIRECT", "update_interval": "24h" },
      { "type": "remote", "tag": "geoip-ru", "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs",
        "download_detour": "DIRECT", "update_interval": "24h" }
    ],
    "final": "LADDER",
    "auto_detect_interface": true,
    "default_domain_resolver": { "server": "dns-ru" }
  }
}
"@

if ($withT2) { $cfg = $cfg.Replace("__T2_OR_EMPTY__", $T2BLOCK) }
else { $cfg = $cfg.Replace("__T2_OR_EMPTY__", "") }

$cfg = $cfg.Replace("__VPS_IP__", $V["VPS_IP"]) `
            .Replace("__DOMAIN__", $V["DOMAIN"]) `
            .Replace("__RPUB__",  $V["REALITY_PUBLIC_KEY"]) `
            .Replace("__SID__",   $V["REALITY_SHORT_ID"]) `
            .Replace("__UUID__",  $V["VLESS_UUID"]) `
            .Replace("__HPW__",   $V["HY2_PASSWORD"]) `
            .Replace("__OBFS__",  $V["HY2_OBFS"]) `
            .Replace("__SNI__",   $V["SNI_MASK"]) `
            .Replace("__T2PATH__", $V["T2_PATH"]) `
            .Replace("__RP__",    $V["REALITY_PORT"]) `
            .Replace("__XP__",    $V["T2_PORT"]) `
            .Replace("__HP__",    $V["HY2_PORT"])

$cfgPath = "$Data\config.json"
[System.IO.File]::WriteAllText($cfgPath, $cfg)
Write-Host "Конфиг отрендерен: $cfgPath"

# Проверка конфига
if (-not (Test-Path "$Bin\sing-box.exe")) { Write-Host "sing-box.exe не найден, проверка пропущена (RenderOnly без бинаря?)" -ForegroundColor Yellow; exit 0 }
& "$Bin\sing-box.exe" check -c $cfgPath
if ($LASTEXITCODE -ne 0) { Write-Host "КОНФИГ НЕ ПРОШЁЛ ПРОВЕРКУ — смотри выше." -ForegroundColor Red; exit 1 }
Write-Host "Проверка конфига: OK"
if ($RenderOnly) { Write-Host "RenderOnly: служба не тронута."; exit 0 }

# ---------- 4. Служба ----------
$binPath = "`"$Bin\sing-box.exe`" run -c `"$cfgPath`""
$svcExists = (Get-Service -Name $Svc -ErrorAction SilentlyContinue) -ne $null
if ($svcExists) {
  Stop-Service $Svc -Force -ErrorAction SilentlyContinue
  Start-Sleep 1
  sc.exe delete $Svc | Out-Null
  Start-Sleep 2
}
New-Service -Name $Svc -BinaryPathName $binPath -DisplayName "Sovereign Node (sing-box ladder)" -StartupType Automatic | Out-Null
sc.exe description $Svc "Sovereign Node: sing-box ladder (Reality/WS-CDN/Hysteria2), TUN, RU-direct" | Out-Null
sc.exe failure $Svc reset= 86400 actions= restart/5000/restart/30000/restart/60000 | Out-Null
Start-Service $Svc
Start-Sleep 4
$s = Get-Service $Svc
if ($s.Status -ne "Running") {
  Write-Host "Служба не поднялась. Логи: $Data\singbox.log ; запрос: sc.exe query $Svc" -ForegroundColor Red
  exit 1
}
Write-Host "Служба $Svc запущена. Лестница живёт." -ForegroundColor Green

# ---------- 5. Проверка выхода ----------
try {
  $ip = (Invoke-WebRequest "https://ifconfig.me" -UseBasicParsing -TimeoutSec 20).Content.Trim()
  Write-Host ("Внешний IP сейчас: {0}  (ожидался VPS {1})" -f $ip, $V["VPS_IP"])
  if ($ip -eq $V["VPS_IP"]) { Write-Host "ТРАССА ПОДТВЕРЖДЕНА: выход через свой узел." -ForegroundColor Green }
  else { Write-Host "IP не совпал — лестница ещё прогревается (urltest) или Cloudflare T2." -ForegroundColor Yellow }
} catch {
  Write-Host "Проверка IP не прошла (лестница может ещё греться ~1 мин). Проверь позже: https://ifconfig.me" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "ГОТОВО. Правила коробки:" -ForegroundColor Green
Write-Host " * RU-сети идут напрямую, всё заблокированное — через лестницу автоматически."
Write-Host " * Если один транспорт умирает, urltest сам переходит на следующий каждые 3 мин."
Write-Host " * Ручное управление (если однажды захочешь): http://127.0.0.1:9090/ui или clash-совместимый клиент."
Write-Host " * Полный стоп/старт: Stop-Service $Svc / Start-Service $Svc"
