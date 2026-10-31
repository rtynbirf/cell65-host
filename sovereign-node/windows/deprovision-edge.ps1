# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — КРАЙ: обратимый съём Cloudflare-слоя
#  powershell -ExecutionPolicy Bypass -File deprovision-edge.ps1 [-Apply] [-DeleteZone]
#
#  По умолчанию — DRY-RUN: только показывает, что БУДЕТ удалено.
#    -Apply        удалить DNS-записи, созданные provision-edge.ps1
#                  (они помечены комментарием "sovereign-node ...")
#    -DeleteZone   снести зону ЦЕЛИКОМ (осторожно: если домен обслуживает
#                  что-то ещё, кроме узла — не делай этого)
#  Зеркально к provision-edge.ps1 (аудит C8: у каждой операции должен быть откат).
#  После съёма: сотри DOMAIN в node.env и перезапусти
#  install-sovereign-node.ps1 — лестница пересоберётся без T2.
# ============================================================
param([switch]$Apply, [switch]$DeleteZone)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$V = @{}
Get-Content (Join-Path $Root "node.env") | ForEach-Object {
  if ($_ -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)\s*$') { $V[$Matches[1]] = $Matches[2].Trim() }
}
if (-not $V["DOMAIN"])   { Write-Host "DOMAIN пуст в node.env — край и так не включён (T2 в лестнице нет)." -ForegroundColor Yellow; exit 0 }
if (-not $V["CF_TOKEN"]) { Write-Host "CF_TOKEN пуст в node.env — нет доступа к Cloudflare." -ForegroundColor Yellow; exit 1 }

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

Write-Host "==> Зона $domain"
$z = CF "GET" "$API/zones?name=$domain"
if ($z.result.Count -eq 0) { Write-Host "Зона не найдена в этом аккаунте — удалять нечего." -ForegroundColor Yellow; exit 0 }
$zid = $z.result[0].id
Write-Host ("    Зона есть (status: {0})" -f $z.result[0].status)

Write-Host "==> DNS-записи sovereign-node в зоне"
$existing = (CF "GET" "$API/zones/$zid/dns_records?per_page=100").result
$mine = @($existing | Where-Object { $_.comment -like "sovereign-node*" })
if ($mine.Count -eq 0) { Write-Host "    Записей с комментарием 'sovereign-node' нет — чисто." -ForegroundColor Yellow }

foreach ($rec in $mine) {
  if ($Apply) {
    $r = CF "DELETE" "$API/zones/$zid/dns_records/$($rec.id)"
    if ($r.success) { Write-Host ("    [удалена] {0} {1} -> {2}" -f $rec.type, $rec.name, $rec.content) -ForegroundColor Green }
    else { Write-Host ("    [ОШИБКА] {0} {1}: {2}" -f $rec.type, $rec.name, ($r.errors | ConvertTo-Json -Compress)) -ForegroundColor Red }
  } else {
    Write-Host ("    [dry-run] {0} {1} -> {2}" -f $rec.type, $rec.name, $rec.content)
  }
}

if ($DeleteZone) {
  if (-not $Apply) {
    Write-Host "==> [dry-run] зона $domain была бы удалена ЦЕЛИКОМ (реально: -Apply -DeleteZone)" -ForegroundColor Red
  } else {
    Write-Host "==> Удаление зоны $domain ЦЕЛИКОМ" -ForegroundColor Red
    $r = CF "DELETE" "$API/zones/$zid"
    if ($r.success) { Write-Host "    зона удалена." -ForegroundColor Green }
    else { Write-Host ("    [ОШИБКА]: " + ($r.errors | ConvertTo-Json -Compress)) -ForegroundColor Red }
  }
}

Write-Host ""
if (-not $Apply) {
  Write-Host "Это был DRY-RUN. Реальное удаление: powershell -File deprovision-edge.ps1 -Apply [-DeleteZone]" -ForegroundColor Cyan
}
Write-Host "СЛЕДУЮЩИЙ ШАГ: сотри DOMAIN в node.env и перезапусти install-sovereign-node.ps1 (от админа) — T2 исчезнет из лестницы." -ForegroundColor Green
