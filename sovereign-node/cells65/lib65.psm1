# ============================================================
# CELL-65 :: lib65.psm1 - общая доска для 64 клеток (модуль)
# Доктрина: ноль удалений, ноль вердиктов - только факты и координаты.
# v2.1: функции флагов/доски самодостаточны (без перекрёстных вызовов),
# загрузка через Import-Module (иммунно к scope-особенностям PS 5.1).
# v2.2: радиус СПБ - точка отсчёта выбора серверов: 59.9386, 30.3141;
# домен РФ отфильтровывается (координата пользователя: вне РФ),
# сортировка: кольцо дистанции от СПБ, затем время HTTP-204.
# ============================================================

$global:CELL65_ROOT = $PSScriptRoot
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Get-Root {
  return $global:CELL65_ROOT
}

function Get-DataDir {
  return (Join-Path (Get-Root) 'data')
}

function Get-LogDir {
  return (Join-Path (Get-Root) 'logs')
}

function Get-BinDir {
  return (Join-Path (Get-Root) 'bin')
}

function Ensure-Dirs {
  foreach ($d in @((Get-DataDir), (Get-LogDir), (Get-BinDir), (Join-Path (Get-DataDir) 'raw'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
  }
}

function Add-Log {
  param([string]$Tag, [string]$Text)
  Ensure-Dirs
  # v8 (аудит): ротация журнала - 10 МБ предохранитель, диск не забивается
  $lf = Join-Path (Get-LogDir) 'cell65.log'
  try { if ((Test-Path $lf) -and ((Get-Item $lf).Length -gt 10MB)) { Move-Item $lf ($lf + '.1') -Force } } catch {}
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Tag, $Text
  Write-Host $line
  try { Add-Content -Path $lf -Value $line -Encoding UTF8 } catch {}
}

# --- клетки: обёртка с отметкой на доске (a1..h8) ---
function Run-Cell {
  param([string]$Row, [int]$Col, [scriptblock]$Body)
  Set-CellState -Row $Row -Col $Col -St 'run'
  try {
    & $Body
    Set-CellState -Row $Row -Col $Col -St 'ok'
    return $true
  } catch {
    Add-Log '!!' ('клетка ' + $Row + $Col + ': ' + $_.Exception.Message)
    Set-CellState -Row $Row -Col $Col -St 'fail'
    return $false
  }
}

# --- сеть: загрузка ---
function Get-Curl {
  if ($env:SystemRoot) {
    $c = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $c) { return $c }
  }
  $w = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($w) { return $w.Source }
  return $null
}

function Invoke-HttpGet {
  param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 25, [string]$Proxy = '')
  Ensure-Dirs
  $c = Get-Curl
  if ($c) {
    $a = @('-sSL','--max-time',"$TimeoutSec",'--fail','-A','CELL65/1.0')
    if ($Proxy -ne '') { $a += @('-x', $Proxy) }
    $a += @('-o', $OutFile, $Url)
    & $c @a 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) { return $true }
  }
  try {
    $h = @{ 'User-Agent' = 'CELL65/1.0' }
    if ($Proxy -ne '') { Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -Proxy $Proxy -UseBasicParsing -Headers $h | Out-Null }
    else { Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing -Headers $h | Out-Null }
    return $true
  } catch { return $false }
}

function Save-RawList {
  param([string]$Src, [object[]]$Files)
  Ensure-Dirs
  # v9: леджер здоровья источников (data\src_health.tsv). 3 сбоя подряд = карантин 24ч -
  # конвейер не тратит время на мёртвых; одиночный сбой НЕ карантин (троттлинг raw/429 - норма).
  $hf = Join-Path (Get-DataDir) 'src_health.tsv'
  $health = @{}
  foreach ($l in @(Get-Content $hf -ErrorAction SilentlyContinue)) {
    $q = $l -split '\|'
    if ($q.Count -ge 6) { $health[$q[0]] = @{ ok = [int]$q[1]; fail = [int]$q[2]; consec = [int]$q[3]; lastok = $q[4]; quar = $q[5] } }
  }
  $h = $health[$Src]
  if ($h -and $h.quar -and $h.quar -ne '') {
    $qUntil = $null
    try { $qUntil = [datetime]$h.quar } catch {}
    if ($qUntil -and $qUntil -gt (Get-Date)) {
      Add-Log 'i' ('источник ' + $Src + ' на карантине до ' + $h.quar + ' (пропущен, ' + $h.consec + ' сбоев подряд)')
      return
    }
  }
  $raw = Join-Path (Get-DataDir) 'raw'
  $okN = 0
  foreach ($f in $Files) {
    $proto = $f[0]; $url = $f[1]
    $out = Join-Path $raw ($Src + '_' + $proto + '.txt')
    $ok = Invoke-HttpGet -Url $url -OutFile $out -TimeoutSec 40
    if (-not $ok) {
      # v9: зеркало jsdelivr - raw.githubusercontent троттлится у части провайдеров, CDN отдаёт тот же файл
      $mj = [regex]::Replace($url, '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.*)$', 'https://cdn.jsdelivr.net/gh/$1/$2@$3/$4')
      if ($mj -ne $url) {
        $ok = Invoke-HttpGet -Url $mj -OutFile $out -TimeoutSec 40
        if ($ok) { Add-Log 'i' ('источник ' + $Src + '/' + $proto + ': взято с зеркала jsdelivr (raw не ответил)') }
      }
    }
    if ($ok) {
      $n = 0
      try { $n = (Get-Content $out).Count } catch {}
      Add-Log 'ok' ('источник ' + $Src + '/' + $proto + ': ' + $n + ' строк')
      $okN++
    } else {
      Add-Log '!!' ('источник ' + $Src + '/' + $proto + ': загрузка не удалась (сеть/код, включая зеркало)')
    }
  }
  if (-not $h) { $h = @{ ok = 0; fail = 0; consec = 0; lastok = ''; quar = '' } }
  if ($okN -gt 0) {
    $h.ok++; $h.consec = 0; $h.quar = ''; $h.lastok = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  } else {
    $h.fail++; $h.consec++
    if ($h.consec -ge 3) {
      $h.quar = (Get-Date).AddHours(24).ToString('yyyy-MM-dd HH:mm:ss')
      Add-Log '!!' ('источник ' + $Src + ': ' + $h.consec + ' сбоев подряд - КАРАНТИН до ' + $h.quar)
    }
  }
  $health[$Src] = $h
  $lines = @()
  foreach ($k in $health.Keys) { $v = $health[$k]; $lines += ($k + '|' + $v.ok + '|' + $v.fail + '|' + $v.consec + '|' + $v.lastok + '|' + $v.quar) }
  $lines | Set-Content $hf -Encoding UTF8
}

# --- замеры ---
function Test-TcpMs {
  param([string]$Ip, [int]$Port, [int]$TimeoutMs = 1500)
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cl = New-Object Net.Sockets.TcpClient
    $ar = $cl.BeginConnect($Ip, $Port, $null, $null)
    if ($ar.AsyncWaitHandle.WaitOne($TimeoutMs) -and $cl.Connected) {
      $cl.EndConnect($ar); $sw.Stop()
      try { $cl.Close() } catch {}
      return [int]$sw.ElapsedMilliseconds
    }
    try { $cl.Close() } catch {}
    return -1
  } catch { return -1 }
}

function Test-HttpViaProxy {
  param([string]$Ip, [int]$Port, [string]$Proto = 'http', [string]$Url = 'http://www.gstatic.com/generate_204', [int]$TimeoutSec = 10)
  $c = Get-Curl
  if (-not $c) { return $false }
  $scheme = $Proto.ToLower()
  if ($scheme -eq 'socks5') { $scheme = 'socks5h' }
  if ($scheme -eq 'socks4') { $scheme = 'socks4a' }
  $px = '{0}://{1}:{2}' -f $scheme, $Ip, $Port
  $out = & $c -s -o NUL --max-time $TimeoutSec -x $px -w '%{http_code}' $Url 2>$null
  return ("$out" -match '^2')
}

# --- v10: реальный трафик через прокси: тело msftconnecttest (204-фейки валятся здесь) ---
function Test-RealViaProxy {
  param([string]$Ip, [int]$Port, [string]$Proto = 'http', [int]$TimeoutSec = 8)
  $c = Get-Curl
  if (-not $c) { return $false }
  $scheme = $Proto.ToLower()
  if ($scheme -eq 'socks5') { $scheme = 'socks5h' }
  if ($scheme -eq 'socks4') { $scheme = 'socks4a' }
  $px = '{0}://{1}:{2}' -f $scheme, $Ip, $Port
  $out = & $c -s --max-time $TimeoutSec -x $px 'http://www.msftconnecttest.com/connecttest.txt' 2>$null
  return ("$out" -match 'Microsoft Connect Test')
}

function Get-GeoFact {
  param([string]$Ip = '')
  Ensure-Dirs
  $u = 'http://ip-api.com/json/?fields=status,message,query,country,countryCode,city,isp,org,as,proxy,hosting'
  if ($Ip -ne '') { $u = ('http://ip-api.com/json/{0}?fields=status,message,query,country,countryCode,city,isp,org,as,proxy,hosting' -f $Ip) }
  $safe = $Ip -replace '[^0-9a-zA-Z\.]', '_'
  if ($safe -eq '') { $safe = 'self' }
  $f = Join-Path (Get-DataDir) ('geo_' + $safe + '.json')
  if (-not (Invoke-HttpGet -Url $u -OutFile $f -TimeoutSec 12)) { return $null }
  try { return (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# --- радиус СПБ: дистанция и кольца (чистая математика, гаверсинус) ---
function Get-DistanceKm {
  param([double]$Lat1, [double]$Lon1, [double]$Lat2, [double]$Lon2)
  $r = 6371.0
  $p1 = $Lat1 * [Math]::PI / 180.0; $p2 = $Lat2 * [Math]::PI / 180.0
  $dp = ($Lat2 - $Lat1) * [Math]::PI / 180.0
  $dl = ($Lon2 - $Lon1) * [Math]::PI / 180.0
  $a = [Math]::Sin($dp / 2.0) * [Math]::Sin($dp / 2.0) + [Math]::Cos($p1) * [Math]::Cos($p2) * [Math]::Sin($dl / 2.0) * [Math]::Sin($dl / 2.0)
  if ($a -gt 1.0) { $a = 1.0 }
  $c = 2.0 * [Math]::ATan2([Math]::Sqrt($a), [Math]::Sqrt(1.0 - $a))
  return [Math]::Round($r * $c, 1)
}

function Get-SpbRing {
  param([double]$DistKm)
  if ($DistKm -le 500) { return 1 }
  if ($DistKm -le 1500) { return 2 }
  if ($DistKm -le 3000) { return 3 }
  if ($DistKm -le 6000) { return 4 }
  return 5
}

# --- гео пачкой (ip-api /batch, до 100 IP за запрос, POST) ---
function Invoke-GeoBatch {
  param([string[]]$Ips)
  $out = @{}
  $ips = @($Ips | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -Unique)
  if ($ips.Count -eq 0) { return $out }
  $u = 'http://ip-api.com/batch?fields=status,message,country,countryCode,city,lat,lon,org,as,query'
  $c = Get-Curl
  $ok = $false
  for ($off = 0; $off -lt $ips.Count; $off += 100) {
    $end = $off + 99
    if ($end -gt $ips.Count - 1) { $end = $ips.Count - 1 }
    $chunk = @($ips[$off..$end])
    $body = '[' + ((@($chunk | ForEach-Object { '"' + $_ + '"' })) -join ',') + ']'
    $bf = Join-Path (Get-DataDir) ('geo_b' + $off + '.json')
    $got = $false
    if ($c) {
      $tmp = Join-Path (Get-DataDir) 'geo_req.json'
      $body | Set-Content -Path $tmp -Encoding ASCII
      & $c -s --max-time 20 -X POST -H 'Content-Type: application/json' --data-binary ('@' + $tmp) $u -o $bf 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Path $bf)) { $got = $true }
    }
    if (-not $got) {
      try {
        $arr = Invoke-RestMethod -Uri $u -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 20
        $arr | ConvertTo-Json -Depth 3 | Set-Content -Path $bf -Encoding UTF8
        $got = $true
      } catch { $got = $false }
    }
    if ($got) {
      try {
        $arr = Get-Content $bf -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($e in @($arr)) { if ($e.query) { $out[[string]$e.query] = $e } }
        $ok = $true
      } catch { $got = $false }
    }
    if ($off + 100 -lt $ips.Count) { Start-Sleep -Seconds 5 }
  }
  if (-not $ok) {
    foreach ($ip in @($ips | Select-Object -First 15)) {
      $g = Get-GeoFact -Ip $ip
      if ($g -and $g.status -eq 'success') { $out[$ip] = $g }
      Start-Sleep -Milliseconds 1600
    }
  }
  return $out
}

# --- v9: универсальная точка отсчёта (дом авто) ---
function Get-HomePoint {
  Ensure-Dirs
  $hf = Join-Path (Get-DataDir) 'home.tsv'
  if (Test-Path $hf) {
    try {
      $q = (Get-Content $hf -Encoding UTF8 | Select-Object -First 1) -split '\|'
      if ($q.Count -ge 3) { return @{ cc = $q[0]; lat = [double]$q[1]; lon = [double]$q[2]; src = 'home.tsv' } }
    } catch {}
  }
  $cc = Get-Flag -Name 'home_cc'; $la = Get-Flag -Name 'home_lat'; $lo = Get-Flag -Name 'home_lon'
  if ($cc -and $la -and $lo) {
    try { return @{ cc = $cc; lat = [double]$la; lon = [double]$lo; src = 'flags' } } catch {}
  }
  return @{ cc = 'RU'; lat = 59.9386; lon = 30.3141; src = 'по умолчанию СПБ' }
}

# v9: соседи (сухопутная граница) для анти-соседского критерия; для остальных домов - правило дистанции (<1200 км)
$script:NB65 = @{
  'RU' = @('BY','UA','GE','AZ','KZ','CN','MN','FI','EE','LV','LT','PL','NO')
  'BY' = @('RU','PL','LT','LV','UA')
  'UA' = @('RU','BY','PL','SK','HU','RO','MD')
  'KZ' = @('RU','CN','KG','UZ','TM')
  'TM' = @('KZ','UZ','IR','AF')
  'UZ' = @('KZ','TM','AF','TJ','KG')
  'IR' = @('TM','AF','PK','IQ','TR','AZ','AM')
  'TR' = @('GR','BG','GE','AM','AZ','IR','IQ','SY')
  'CN' = @('RU','MN','KZ','KG','TJ','AF','PK','IN','NP','MM','LA','VN','KP')
  'AM' = @('GE','AZ','IR','TR')
  'AZ' = @('RU','GE','AM','IR','TR')
  'GE' = @('RU','AM','AZ','TR')
  'FI' = @('RU','SE','NO','EE')
  'EE' = @('RU','LV','FI')
  'LV' = @('LT','EE','RU','BY')
  'LT' = @('LV','BY','PL','RU')
  'PL' = @('DE','CZ','SK','UA','BY','LT','RU')
  'MD' = @('RO','UA')
  'RO' = @('HU','RS','BG','MD','UA')
  'NO' = @('SE','FI','RU')
  'SE' = @('NO','FI')
  'AF' = @('IR','TM','UZ','TJ','PK','CN')
  'PK' = @('IR','AF','CN','IN')
  'IQ' = @('IR','TR','SY','SA','JO','KW')
  'SY' = @('TR','IQ','JO','LB','IL')
  'IN' = @('PK','CN','NP','BD','MM')
}

function Get-NeighborPenalty {
  param([string]$HomeCc, [string]$ExitCc, [double]$DistKm)
  if ($ExitCc -eq '' -or $ExitCc -eq '??') { return 0 }
  $nb = $script:NB65[$HomeCc]
  if ($nb -and @($nb) -contains $ExitCc) { return 1 }
  if ($DistKm -ge 0 -and $DistKm -lt 1200) { return 1 }
  return 0
}

# --- v9: меритократия (леджер data\score.tsv): лидер держится заслугами ---
function Get-ScoreMap {
  Ensure-Dirs
  $m = @{}
  foreach ($l in @(Get-Content (Join-Path (Get-DataDir) 'score.tsv') -ErrorAction SilentlyContinue)) {
    $q = $l -split '\|'
    if ($q.Count -ge 2) { $sc = 0.0; [void][double]::TryParse($q[1], [ref]$sc); $m[$q[0].Replace('#','|')] = $sc }
  }
  return $m
}

function Update-Score {
  param([string]$Key, [double]$Delta, [double]$Mult = -1.0)
  Ensure-Dirs
  $f = Join-Path (Get-DataDir) 'score.tsv'
  $map = Get-ScoreMap
  $cur = 50.0
  if ($map.ContainsKey($Key)) { $cur = $map[$Key] }
  if ($Mult -ge 0) { $cur = $cur * $Mult } else { $cur = $cur + $Delta }
  if ($cur -gt 1000.0) { $cur = 1000.0 }
  $map[$Key] = [Math]::Round($cur, 1)
  $lines = @()
  # v9: '|' в ключе экранируется в '#' - ключ proto|ip|port не должен ломать TSV
  foreach ($k in $map.Keys) { $lines += ($k.Replace('|','#') + '|' + $map[$k]) }
  $lines | Set-Content $f -Encoding UTF8
  return $map[$Key]
}

function Age-Scores {
  Ensure-Dirs
  $f = Join-Path (Get-DataDir) 'score.tsv'
  $map = Get-ScoreMap
  if ($map.Count -eq 0) { return }
  $lines = @()
  foreach ($k in $map.Keys) {
    $v = [Math]::Round($map[$k] * 0.9, 1)
    if ($v -ge 3.0) { $lines += ($k.Replace('|','#') + '|' + $v) }
  }
  $lines | Set-Content $f -Encoding UTF8
}

# --- v9: универсальное ранжирование: дом авто, не дом-страна, соседи в хвост, класс дальности, разнообразие org ---
function Get-RankedUniversal {
  param([string]$GeoTsv = 'geo.tsv', [int]$OrgCap = 2)
  $hp = Get-HomePoint
  $p = Join-Path (Get-DataDir) $GeoTsv
  $rows = @()
  if (Test-Path $p) {
    foreach ($l in @(Get-Content $p -Encoding UTF8)) {
      $q = $l -split '\|'
      if ($q.Count -lt 9) { continue }
      $org = ''
      if ($q.Count -ge 10) { $org = $q[9] }
      $rows += New-Object PSObject -Property @{
        proto = $q[0]; host = $q[1]; port = [int]$q[2]; t = [double]$q[3]
        cc = $q[4]; country = $q[5]; city = $q[6]; dist_km = [double]$q[7]; ring = [int]$q[8]; org = $org
      }
    }
  }
  $homeN = 0
  $scoreMap = Get-ScoreMap
  $cands = @()
  foreach ($r in $rows) {
    if ($r.cc -eq $hp.cc) { $homeN++; continue }
    $nb = Get-NeighborPenalty -HomeCc $hp.cc -ExitCc $r.cc -DistKm $r.dist_km
    $key = $r.proto + '|' + $r.host + '|' + $r.port
    $sc = 50.0
    if ($scoreMap.ContainsKey($key)) { $sc = $scoreMap[$key] }
    $r | Add-Member NoteProperty neighbor $nb -Force
    $r | Add-Member NoteProperty score $sc -Force
    $cands += $r
  }
  $cands = @($cands | Sort-Object -Property @{e='neighbor';Descending=$false}, @{e='score';Descending=$true}, @{e='ring';Descending=$false}, @{e='t';Descending=$false})
  $orgCount = @{}
  $final = @()
  foreach ($c in $cands) {
    $o = ''
    if ($c.PSObject.Properties['org']) { $o = [string]$c.org }
    if ($o -ne '') {
      if (-not $orgCount.ContainsKey($o)) { $orgCount[$o] = 0 }
      if ($orgCount[$o] -ge $OrgCap) { continue }
      $orgCount[$o]++
    }
    $final += $c
  }
  return New-Object PSObject -Property @{ ranked = $final; home = $hp; homeN = $homeN; total = $rows.Count }
}

# --- чтение geo.tsv и ранжирование: вне РФ, кольцо СПБ, затем время ---
function Get-SpbRanked {
  param([string]$GeoTsv = 'geo.tsv')
  $p = Join-Path (Get-DataDir) $GeoTsv
  $rows = @()
  if (Test-Path $p) {
    foreach ($l in @(Get-Content $p -Encoding UTF8)) {
      $q = $l -split '\|'
      if ($q.Count -lt 9) { continue }
      $rows += New-Object PSObject -Property @{
        proto = $q[0]; host = $q[1]; port = [int]$q[2]; t = [double]$q[3]
        cc = $q[4]; country = $q[5]; city = $q[6]; dist_km = [double]$q[7]; ring = [int]$q[8]
      }
    }
  }
  $ru = @($rows | Where-Object { $_.cc -eq 'RU' })
  $keep = @($rows | Where-Object { $_.cc -ne 'RU' } | Sort-Object -Property ring, t)
  return New-Object PSObject -Property @{ ranked = $keep; ru = $ru.Count; total = $rows.Count }
}

# --- параллельная проба (runspace pool, PS 5.1) ---
function Invoke-Parallel {
  param([object[]]$Items, [scriptblock]$Body, [int]$Throttle = 24)
  if (-not $Items -or $Items.Count -eq 0) { return @() }
  $pool = [runspacefactory]::CreateRunspacePool(1, $Throttle); $pool.Open()
  $jobs = @()
  foreach ($it in $Items) {
    $p = [powershell]::Create(); $p.RunspacePool = $pool
    [void]$p.AddScript($Body.ToString()).AddArgument($it)
    $jobs += ,@($p, $p.BeginInvoke())
  }
  $out = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $jobs.Count; $i++) {
    try { $r = $jobs[$i][0].EndInvoke($jobs[$i][1]); if ($r) { foreach ($x in $r) { [void]$out.Add([string]$x) } } }
    catch {}
    finally { try { $jobs[$i][0].Dispose() } catch {} }
  }
  $pool.Close()
  return $out
}

# --- состояние: чтение json-карты ---
function Get-StateMap {
  param([string]$File = 'board.json')
  Ensure-Dirs
  $p = Join-Path (Get-DataDir) $File
  $m = @{}
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($pr in $j.PSObject.Properties) { $m[$pr.Name] = [string]$pr.Value }
    } catch {}
  }
  return $m
}

# --- флаги (самодостаточно, без перекрёстных вызовов) ---
function Get-Flag {
  param([string]$Name)
  Ensure-Dirs
  $p = Join-Path (Get-DataDir) 'flags.json'
  if (-not (Test-Path $p)) { return '' }
  try {
    $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$j.$Name
  } catch { return '' }
}

function Set-Flag {
  param([string]$Name, [string]$Value)
  Ensure-Dirs
  $p = Join-Path (Get-DataDir) 'flags.json'
  $m = @{}
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($pr in $j.PSObject.Properties) { $m[$pr.Name] = [string]$pr.Value }
    } catch {}
  }
  $m[$Name] = $Value
  $m | ConvertTo-Json | Set-Content -Path $p -Encoding UTF8
}

# --- доска (самодостаточно, без перекрёстных вызовов) ---
function Set-CellState {
  param([string]$Row, [int]$Col, [string]$St)
  Ensure-Dirs
  $p = Join-Path (Get-DataDir) 'board.json'
  $m = @{}
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($pr in $j.PSObject.Properties) { $m[$pr.Name] = [string]$pr.Value }
    } catch {}
  }
  $m[($Row + $Col)] = $St
  $m | ConvertTo-Json | Set-Content -Path $p -Encoding UTF8
}

function Get-BoardText {
  $m = Get-StateMap -File 'board.json'
  $rows = @('a','b','c','d','e','f','g','h')
  $names = @('среда','сеть','списки','проба','локаль','vpn','прокси ОС','жизнь')
  $lines = @()
  $lines += ''
  $lines += '     1  2  3  4  5  6  7  8    (8x8 = 64 клетки; 65-я = диспетчер)'
  for ($r = 0; $r -lt 8; $r++) {
    $line = ' ' + $rows[$r] + '  '
    for ($c = 1; $c -le 8; $c++) {
      $st = [string]$m[$rows[$r] + $c]
      $ch = '.'
      if ($st -eq 'ok') { $ch = 'o' }
      elseif ($st -eq 'fail') { $ch = 'x' }
      elseif ($st -eq 'run') { $ch = '>' }
      $line += "$ch  "
    }
    $line += ' ' + $names[$r]
    $lines += $line
  }
  $lines += '     . не запускалась   o факт: ок   x факт: сбой   > выполняется'
  return $lines
}

function Show-Board {
  $t = Get-BoardText
  foreach ($l in $t) { Write-Host $l }
}

function Show-KeyFacts {
  $d = Get-DataDir
  $bf = Join-Path $d 'best.json'
  if (Test-Path $bf) {
    try {
      $b = Get-Content $bf -Raw -Encoding UTF8 | ConvertFrom-Json
      $extra = ''
      if ($b.PSObject.Properties['ring']) { $extra = ' | R' + $b.ring + ' ' + $b.cc + ' ' + $b.dist_km + ' км от дома' }
      Write-Host (' выбор (d6): ' + $b.proto + ' ' + $b.ip + ':' + $b.port + ' | HTTP-204 за ' + $b.http_s + ' c' + $extra + ' | ' + $b.ts)
    } catch {}
  } else { Write-Host ' выбор (d6): ещё не делался (меню [3])' }
  $g = Get-Flag -Name 'gost_ok'
  if ($g -eq '1') {
    Write-Host ' локальный прокси (e): 127.0.0.1:18080 (HTTP) / 127.0.0.1:18081 (SOCKS5) - отвечает'
    Write-Host ' мост: браузер пока может идти напрямую - заблокированные сайты не откроются; направь плагин на локаль (СЕРВЕРЫ -> 127.0.0.1:18080) или включи системный прокси (g2)'
  } else { Write-Host ' локальный прокси (e): не запущен / не проверен' }
  $v = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
  if ($v -and $null -ne $v.ProxyEnable -and [int]$v.ProxyEnable -eq 1) { Write-Host (' системный прокси (g): ВКЛ ' + $v.ProxyServer) }
  else { Write-Host ' системный прокси (g): выкл' }
  if (Test-Path (Join-Path $d 'installed.flag')) { Write-Host ' автоустановка (h): да (задача CELL65 при входе)' }
  else { Write-Host ' автоустановка (h): нет (координата: меню [7])' }
}

# --- применение системного прокси: уведомление WinInet ---
function Invoke-WinInetRefresh {
  try {
    if (-not ('CELL65.WInet' -as [type])) {
      Add-Type -TypeDefinition 'namespace CELL65 { public static class WInet { [System.Runtime.InteropServices.DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(System.IntPtr h, int opt, System.IntPtr buf, int len); public static void Refresh() { InternetSetOption(System.IntPtr.Zero, 39, System.IntPtr.Zero, 0); InternetSetOption(System.IntPtr.Zero, 37, System.IntPtr.Zero, 0); } } }'
    }
    [CELL65.WInet]::Refresh()
    return $true
  } catch { return $false }
}


# v11: официальные IPv4-сети Cloudflare (cloudflare.com/ips-v4, сфетчено 07.11.2026).
# Прокси там быть не может: это CDN-грани и страницы ошибок 502/1015, которые сырые
# списки иногда отдают строками, похожими на ip:порт. Зеркало в ext: C65.CF_NETS.
$script:CfNets = @(
  @{ n = @([byte]173,[byte]245,[byte]48,[byte]0);   t = 20 },
  @{ n = @([byte]103,[byte]21,[byte]244,[byte]0);   t = 22 },
  @{ n = @([byte]103,[byte]22,[byte]200,[byte]0);   t = 22 },
  @{ n = @([byte]103,[byte]31,[byte]4,[byte]0);     t = 22 },
  @{ n = @([byte]141,[byte]101,[byte]64,[byte]0);   t = 18 },
  @{ n = @([byte]108,[byte]162,[byte]192,[byte]0);  t = 18 },
  @{ n = @([byte]190,[byte]93,[byte]240,[byte]0);   t = 20 },
  @{ n = @([byte]188,[byte]114,[byte]96,[byte]0);   t = 20 },
  @{ n = @([byte]197,[byte]234,[byte]240,[byte]0);  t = 22 },
  @{ n = @([byte]198,[byte]41,[byte]128,[byte]0);   t = 17 },
  @{ n = @([byte]162,[byte]158,[byte]0,[byte]0);    t = 15 },
  @{ n = @([byte]104,[byte]16,[byte]0,[byte]0);     t = 13 },
  @{ n = @([byte]104,[byte]24,[byte]0,[byte]0);     t = 14 },
  @{ n = @([byte]172,[byte]64,[byte]0,[byte]0);     t = 13 },
  @{ n = @([byte]131,[byte]0,[byte]72,[byte]0);     t = 22 }
) | ForEach-Object {
  $mb = [byte[]]@(0, 0, 0, 0)
  for ($i = 0; $i -lt 4; $i++) {
    $take = [Math]::Max(0, [Math]::Min(8, $_['t'] - 8 * $i))
    if ($take -gt 0) { $mb[$i] = [byte](256 - [Math]::Pow(2, 8 - $take)) }
  }
  @{ n = $_['n']; b = $mb }
}

function Test-CfIp {
  param([string]$Ip)
  if ($Ip -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') { return $false }
  $ipb = ([System.Net.IPAddress]::Parse($Ip)).GetAddressBytes()
  foreach ($w in $script:CfNets) {
    $ok = $true
    for ($i = 0; $i -lt 4; $i++) { if (($ipb[$i] -band $w['b'][$i]) -ne ($w['n'][$i] -band $w['b'][$i])) { $ok = $false; break } }
    if ($ok) { return $true }
  }
  return $false
}

# --- самопроверка модуля: факт, если что-то не определилось ---
$cell65Required = @(
  'Get-Root','Get-DataDir','Get-LogDir','Get-BinDir','Ensure-Dirs','Add-Log',
  'Run-Cell','Get-Curl','Invoke-HttpGet','Save-RawList','Test-TcpMs',
  'Test-HttpViaProxy','Get-GeoFact','Invoke-Parallel','Get-StateMap',
  'Get-Flag','Set-Flag','Set-CellState','Get-BoardText','Show-Board',
  'Show-KeyFacts','Invoke-WinInetRefresh','Test-CfIp',
  'Get-DistanceKm','Get-SpbRing','Invoke-GeoBatch','Get-SpbRanked'
)
foreach ($f in $cell65Required) {
  if (-not (Get-Command -Name $f -ErrorAction SilentlyContinue)) {
    Write-Host ('[CELL-65] ФАКТ: функция модуля не определилась: ' + $f)
  }
}

Export-ModuleMember -Function *
