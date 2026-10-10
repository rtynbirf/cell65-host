# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — КРАЙ: провижининг домена в Cloudflare
#  powershell -ExecutionPolicy Bypass -File provision-edge.ps1 [-Wait]
#
#  Что делает (по API-токену из node.env):
#    1. Создаёт зону твоего домена в аккаунте Cloudflare (или находит существующую)
#    2. Включает SSL-режим Full
#    3. Создаёт DNS-записи:
#         A  @      -> VPS_IP   (proxied, через CDN)   <- путь T2
#         A  direct -> VPS_IP   (только DNS, для диагностики)
#         AAAA @    -> VPS_IPV6 (proxied, если указан)
#    4. Показывает nameserver'ы, которые надо выставить у регистратора
#  После успеха перезапусти install-sovereign-node.ps1 — включится T2.
# ============================================================
param([switch]$Wait)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$V = @{}
Get-Content (Join-Path $Root "node.env") | ForEach-Object {
  if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') { $V[$Matches[1]] = $Matches[2].Trim() }
}
if (-not $V["DOMAIN"])   { Write-Host "DOMAIN пуст в node.env — сначала впиши домен." -ForegroundColor Yellow; exit 1 }
if (-not $V["CF_TOKEN"]) { Write-Host "CF_TOKEN пуст в node.env — нет мандата на Cloudflare." -ForegroundColor Yellow; exit 1 }
if (-not $V["VPS_IP"])   { Write-Host "VPS_IP пуст — домен некуда направлять." -ForegroundColor Yellow; exit 1 }

$H = @{ "Authorization" = "Bearer $($V['CF_TOKEN'])"; "Content-Type" = "application/json" }
$API = "https://api.cloudflare.com/client/v4"
$domain = $V["DOMAIN"].ToLowerInvariant()

function CF($Method, $Uri, $Body) {
  $json = if ($Body) { $Body | ConvertTo-Json -Depth 8 -Compress } else { $null }
  try {
    $r = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $H -Body $json -TimeoutSec 30
    return $r
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $sr = New-Object IO.StreamReader($resp.GetResponseStream())
      $raw = $sr.ReadToEnd()
      try { return $raw | ConvertFrom-Json } catch { Write-Host "HTTP ошибка: $raw" -ForegroundColor Red; exit 1 }
    }
    throw
  }
}

Write-Host "==> 1/4 Зона $domain"
$z = CF "GET" "$API/zones?name=$domain"
if ($z.result.Count -gt 0) {
  $zone = $z.result[0]; $zid = $zone.id
  Write-Host "    Зона уже есть (status: $($zone.status))"
} else {
  $body = @{ name = $domain; account = @{ id = $V["CF_ACCOUNT_ID"] }; type = "full" }
  $r = CF "POST" "$API/zones" $body
  if (-not $r.success) { Write-Host ("Не смог создать зону: " + ($r.errors | ConvertTo-Json -Compress)) -ForegroundColor Red; exit 1 }
  $zone = $r.result; $zid = $zone.id
  Write-Host "    Зона создана (status: $($zone.status))"
}

Write-Host "==> 2/4 Nameserver'ы для регистратора:"
$zone.name_servers | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor Cyan }
Write-Host "    Выстави ИХ у регистратора домена (замени текущие NS). Изменение вступает от минут до часов."

Write-Host "==> 3/4 SSL режим Full"
CF "PATCH" "$API/zones/$zid/settings/ssl" @{ value = "full" } | Out-Null
Write-Host "    OK"

Write-Host "==> 4/4 DNS записи"
$recs = @(
  @{ type = "A"; name = "@";      content = $V["VPS_IP"]; proxied = $true;  ttl = 1; comment = "sovereign-node T2 origin (CDN)" },
  @{ type = "A"; name = "direct"; content = $V["VPS_IP"]; proxied = $false; ttl = 1; comment = "sovereign-node raw (diagnostics)" }
)
if ($V["VPS_IPV6"]) { $recs += @{ type = "AAAA"; name = "@"; content = $V["VPS_IPV6"]; proxied = $true; ttl = 1; comment = "sovereign-node T2 origin v6" } }

$existing = (CF "GET" "$API/zones/$zid/dns_records?per_page=100").result
foreach ($rec in $recs) {
  $same = $existing | Where-Object { $_.type -eq $rec.type -and $_.name -in ("$domain", $rec.name + ".$domain") -and $_.content -eq $rec.content }
  if ($same) { Write-Host ("    [есть]  {0} {1} -> {2}" -f $rec.type, $rec.name, $rec.content); continue }
  $r = CF "POST" "$API/zones/$zid/dns_records" $rec
  if ($r.success) { Write-Host ("    [созд]  {0} {1} -> {2} (proxied={3})" -f $rec.type, $rec.name, $rec.content, $rec.proxied) -ForegroundColor Green }
  else { Write-Host ("    [ОШИБКА] {0} {1}: {2}" -f $rec.type, $rec.name, ($r.errors | ConvertTo-Json -Compress)) -ForegroundColor Red }
}

if ($zone.status -ne "active") {
  Write-Host ""
  Write-Host "Зона ещё НЕ активна ($($zone.status)). Это нормально." -ForegroundColor Yellow
  if ($Wait) {
    Write-Host "Жду активации (проверка каждые 30 сек, максимум 20 мин; Ctrl+C чтобы прервать)..."
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep 30
      $z2 = CF "GET" "$API/zones/$zid"
      if ($z2.result.status -eq "active") { Write-Host "ЗОНА АКТИВНА." -ForegroundColor Green; break }
      Write-Host ("    [" + ($i+1) + "] " + $z2.result.status)
    }
  } else {
    Write-Host "После смены NS у регистратора запусти: powershell -File provision-edge.ps1 -Wait  (или просто перезапусти этот скрипт — он идемпотентен)."
  }
}

Write-Host ""
Write-Host "СЛЕДУЮЩИЙ ШАГ: перезапусти install-sovereign-node.ps1 (от админа)." -ForegroundColor Green
Write-Host "Он увидит DOMAIN в node.env, соберёт T2 через Cloudflare и рестартует службу."
