# CELL-65 :: c04_probe.ps1 - ряд D: ПРОБА и ВЫБОР (клетки d1..d8)
# Замеры: TCP-соединение (мс) и живой HTTP-запрос через прокси (generate_204).
# Выбор (v3) = радиус СПБ (59.9386,30.3141): вне домена РФ, кольцо дистанции,
# затем скорость. Гео - пачкой ip-api /batch. Это факт замера, не вердикт.
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

$script:BodyTcp = {
  param($e)
  $p = $e -split '\|'
  $ip = $p[1]; $port = 0
  [void][int]::TryParse($p[2], [ref]$port)
  $ms = -1
  try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cl = New-Object Net.Sockets.TcpClient
    $ar = $cl.BeginConnect($ip, $port, $null, $null)
    if ($ar.AsyncWaitHandle.WaitOne(1500) -and $cl.Connected) { $cl.EndConnect($ar); $sw.Stop(); $ms = [int]$sw.ElapsedMilliseconds }
    try { $cl.Close() } catch {}
  } catch { $ms = -1 }
  if ($ms -ge 0) { return ($p[0] + '|' + $ip + '|' + $p[2] + '|' + $ms) }
  return $null
}

$script:BodyTcp3 = {
  param($e)
  $p = $e -split '\|'
  $ip = $p[1]; $port = 0
  [void][int]::TryParse($p[2], [ref]$port)
  $ts = @()
  for ($i = 0; $i -lt 3; $i++) {
    $ms = -1
    try {
      $sw = [Diagnostics.Stopwatch]::StartNew()
      $cl = New-Object Net.Sockets.TcpClient
      $ar = $cl.BeginConnect($ip, $port, $null, $null)
      if ($ar.AsyncWaitHandle.WaitOne(1500) -and $cl.Connected) { $cl.EndConnect($ar); $sw.Stop(); $ms = [int]$sw.ElapsedMilliseconds }
      try { $cl.Close() } catch {}
    } catch { $ms = -1 }
    if ($ms -ge 0) { $ts += $ms }
    Start-Sleep -Milliseconds 250
  }
  if ($ts.Count -ge 2) {
    $ts = @($ts | Sort-Object)
    $med = $ts[[int](($ts.Count - 1) / 2)]
    return ($p[0] + '|' + $ip + '|' + $p[2] + '|' + $med)
  }
  return $null
}

$script:BodyHttp = {
  param($e)
  $p = $e -split '\|'
  $proto = $p[0]; $ip = $p[1]; $port = $p[2]
  $sc = $proto
  if ($sc -eq 'socks5') { $sc = 'socks5h' }
  if ($sc -eq 'socks4') { $sc = 'socks4a' }
  $px = $sc + '://' + $ip + ':' + $port
  $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
  if (-not (Test-Path $curl)) { return $null }
  # v10: три цели. (1) gstatic 204 по HTTP; (2) реальное тело msftconnecttest - валят
  # прозрачные фейки, которые сами отвечают 204 БЕЗ выхода в интернет ("подключились
  # к серверу без интернета"); (3) HTTPS CONNECT-туннель. 407 = узел требует
  # авторизацию - отдельная категория AUTH (в пробе больше не тратится).
  $o = & $curl -s -o NUL --max-time 8 -x $px -w '%{http_code} %{time_total}' 'http://www.gstatic.com/generate_204' 2>$null
  $s = "$o"
  if ($LASTEXITCODE -ne 0 -or $s -notmatch '^(2\d\d) ([0-9\.]+)$') {
    if ($s -match '^407') { return ($proto + '|' + $ip + '|' + $port + '|AUTH|0') }
    return $null
  }
  $t1 = $Matches[2]
  $okReal = $false
  $o2 = & $curl -s --max-time 8 -x $px 'http://www.msftconnecttest.com/connecttest.txt' 2>$null
  if ($LASTEXITCODE -eq 0 -and ("$o2") -match 'Microsoft Connect Test') { $okReal = $true }
  $okTls = $false
  $o3 = & $curl -s -o NUL --max-time 8 -x $px -w '%{http_code}' 'https://www.gstatic.com/generate_204' 2>$null
  if ($LASTEXITCODE -eq 0 -and ("$o3") -match '^2') { $okTls = $true }
  $v = 'OK1'
  if ($okReal -and $okTls) { $v = 'OK3' } elseif ($okReal -or $okTls) { $v = 'OK2' }
  return ($proto + '|' + $ip + '|' + $port + '|' + $v + '|' + $t1)
}

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'd' 1 {
    $pool = Join-Path (Get-DataDir) 'pool.tsv'
    if (-not (Test-Path $pool)) { Add-Log '!!' 'пула нет (координата: ряд c)'; return }
    $all = @(Get-Content $pool)
    $samp = @()
    # v10: узлы, ответившие 407 в прошлых пробах, из выборки исключены - время пробы не тратится
    $authf1 = Join-Path (Get-DataDir) 'auth407.tsv'
    $authKeys = @()
    if (Test-Path $authf1) { $authKeys = @(Get-Content $authf1 -Encoding UTF8 | ForEach-Object { $q1 = $_ -split '\|'; ($q1[0] + '|' + $q1[1] + '|' + $q1[2]) }) }
    $nAuthCut = 0
    foreach ($spec in @(@('http', 220), @('socks5', 220), @('socks4', 60))) {
      $sub = @($all | Where-Object { $_.StartsWith($spec[0] + '|') })
      if ($authKeys.Count -gt 0) {
        $subAll = $sub.Count
        $sub = @($sub | Where-Object { $ak = ($_ -split '\|')[0..2] -join '|'; -not ($authKeys -contains $ak) })
        $nAuthCut += ($subAll - $sub.Count)
      }
      if ($sub.Count -eq 0) { Add-Log 'i' ('выборка ' + $spec[0] + ': пусто'); continue }
      $n = [Math]::Min($spec[1], $sub.Count)
      $pick = @(Get-Random -InputObject $sub -Count $n)
      $samp = @($samp + $pick)
      Add-Log 'i' ('выборка ' + $spec[0] + ': ' + $n + ' из ' + $sub.Count)
    }
    if ($nAuthCut -gt 0) { Add-Log 'i' ('исключены из выборки 407-узлы прошлых проб: ' + $nAuthCut) }
    # v9: лидер всегда в выборке - меритократия требует перепроверки действующего узла
    $b = Join-Path (Get-DataDir) 'best.json'
    if (Test-Path $b) {
      try {
        $bb = Get-Content $b -Raw -Encoding UTF8 | ConvertFrom-Json
        $bk = $bb.proto + '|' + $bb.ip + '|' + $bb.port
        if (@($samp | Where-Object { $_.StartsWith($bk + '|') }).Count -eq 0 -and @($all | Where-Object { $_.StartsWith($bk + '|') }).Count -gt 0) {
          $samp = @($samp + ($bk + '|leader'))
          Add-Log 'i' ('лидер добавлен в выборку: ' + $bk)
        }
      } catch {}
    }
    $samp | Set-Content (Join-Path (Get-DataDir) 'sample.tsv') -Encoding UTF8
    Add-Log 'i' ('выборка всего: ' + $samp.Count + ' кандидатов')
  } }

  2 { Run-Cell 'd' 2 {
    $sf = Join-Path (Get-DataDir) 'sample.tsv'
    if (-not (Test-Path $sf)) { Add-Log '!!' 'sample.tsv нет (координата: d1)'; return }
    $items = @(Get-Content $sf | ForEach-Object { ($_ -split '\|')[0..2] -join '|' })
    Add-Log 'i' ('TCP-проба: ' + $items.Count + ' кандидатов, поток 32, таймаут 1.5с')
    $res = @(Invoke-Parallel -Items $items -Body $script:BodyTcp -Throttle 32)
    $res | Set-Content (Join-Path (Get-DataDir) 'tcp_ok.tsv') -Encoding UTF8
    Add-Log 'ok' ('TCP ответили: ' + $res.Count + ' из ' + $items.Count)
  } }

  3 { Run-Cell 'd' 3 {
    $tf = Join-Path (Get-DataDir) 'tcp_ok.tsv'
    if (-not (Test-Path $tf)) { Add-Log '!!' 'tcp_ok.tsv нет (координата: d2)'; return }
    $items = @(Get-Content $tf | ForEach-Object { ($_ -split '\|')[0..2] -join '|' })
    if ($items.Count -eq 0) { Add-Log '!!' 'TCP: ни один не ответил'; return }
    Add-Log 'i' ('3 замера на кандидата (' + $items.Count + ' шт), медиана')
    $res = @(Invoke-Parallel -Items $items -Body $script:BodyTcp3 -Throttle 24)
    $ranked = @($res | ForEach-Object {
      $q = $_ -split '\|'
      New-Object PSObject -Property @{ proto = $q[0]; ip = $q[1]; port = $q[2]; ms = [int]$q[3] }
    })
    $top = @()
    foreach ($pr in @('http', 'socks5', 'socks4')) {
      $top = @($top + @($ranked | Where-Object { $_.proto -eq $pr } | Sort-Object ms | Select-Object -First 20))
    }
    $lines = @($top | ForEach-Object { $_.proto + '|' + $_.ip + '|' + $_.port + '|' + $_.ms })
    $lines | Set-Content (Join-Path (Get-DataDir) 'top.tsv') -Encoding UTF8
    Add-Log 'ok' ('топ по TCP: ' + $lines.Count + ' (до 20 на протокол)')
  } }

  4 { Run-Cell 'd' 4 {
    $tf = Join-Path (Get-DataDir) 'top.tsv'
    if (-not (Test-Path $tf)) { Add-Log '!!' 'top.tsv нет (координата: d3)'; return }
    $items = @(Get-Content $tf)
    if ($items.Count -eq 0) { Add-Log '!!' 'топ пуст'; return }
    Add-Log 'i' ('живая проверка (204 + реальный трафик + HTTPS) через прокси: ' + $items.Count + ' шт')
    $res = @(Invoke-Parallel -Items $items -Body $script:BodyHttp -Throttle 12)
    $res = @($res | Where-Object { $_ })
    $auth = @($res | Where-Object { ($_ -split '\|')[3] -eq 'AUTH' })
    $oks = @($res | Where-Object { ($_ -split '\|')[3] -match '^OK' })
    $full = @($oks | Where-Object { ($_ -split '\|')[3] -eq 'OK3' })
    if ($auth.Count -gt 0) {
      $af = Join-Path (Get-DataDir) 'auth407.tsv'
      $old = @(); if (Test-Path $af) { $old = @(Get-Content $af -Encoding UTF8) }
      $keys = @{}
      foreach ($l in $old) { $q = $l -split '\|'; if ($q.Count -ge 3) { $keys[($q[0] + '|' + $q[1] + '|' + $q[2])] = 1 } }
      $add = @($auth | Where-Object { $q = $_ -split '\|'; -not $keys.ContainsKey(($q[0] + '|' + $q[1] + '|' + $q[2])) })
      if ($add.Count -gt 0) { Add-Content -Path $af -Value $add -Encoding UTF8 }
      Add-Log 'i' ('407-авторизация: ' + $auth.Count + ' шт -> чёрный список auth407.tsv (проба их больше не тратит)')
    }
    $oks | Set-Content (Join-Path (Get-DataDir) 'http_ok.tsv') -Encoding UTF8
    Add-Log 'ok' ('живые: ' + $oks.Count + ' из ' + $items.Count + ' (полные OK3: ' + $full.Count + ' | частичные: ' + ($oks.Count - $full.Count) + ' | 407: ' + $auth.Count + ')')
  } }

  5 { Run-Cell 'd' 5 {
    $hf = Join-Path (Get-DataDir) 'http_ok.tsv'
    if (-not (Test-Path $hf)) { Add-Log '!!' 'http_ok.tsv нет (координата: d4)'; return }
    $lines = @(Get-Content $hf | Where-Object { $f5 = $_ -split '\|'; ($f5.Count -ge 5) -and ($f5[3] -match '^OK') })
    if ($lines.Count -eq 0) { Add-Log '!!' 'живых кандидатов: 0 - гео нечего мерить (координата: повторить ряды c и d)'; return }
    # v10: $home в PowerShell - переменная только для чтения ("Не удается перезаписать
    # переменную HOME" - живой краш d5 на машине 6ORMAN); переименовано в $hp
    $hp = Get-HomePoint
    $ips = @($lines | ForEach-Object { ($_ -split '\|')[1] } | Select-Object -Unique)
    Add-Log 'i' ('гео-батч ip-api: ' + $ips.Count + ' IP | точка отсчёта: дом ' + $hp.cc + ' (' + $hp.lat + ',' + $hp.lon + ' | ' + $hp.src + ')')
    $geo = Invoke-GeoBatch -Ips $ips
    $out = @()
    foreach ($l in $lines) {
      $q = $l -split '\|'
      $cc = '??'; $cn = '-'; $city = '-'; $lat = $null; $lon = $null; $org = ''
      if ($geo.ContainsKey($q[1])) {
        $g = $geo[$q[1]]
        if ($g.status -eq 'success') { $cc = $g.countryCode; $cn = $g.country; $city = $g.city; $lat = [double]$g.lat; $lon = [double]$g.lon; $org = [string]$g.org }
      }
      $dist = -1.0; $ring = 9
      if ($null -ne $lat) {
        # v9: дистанция от ДОМА (авто-определение), а не от СПБ
        $dist = Get-DistanceKm -Lat1 $hp.lat -Lon1 $hp.lon -Lat2 $lat -Lon2 $lon
        $ring = Get-SpbRing -DistKm $dist
      }
      # v8 (аудит): '|' внутри гео-данных сдвинул бы колонки TSV - чистим на писателе
      $cc = [string]$cc -replace '\|', '/'
      $cn = [string]$cn -replace '\|', '/'
      $city = [string]$city -replace '\|', '/'
      $org = [string]$org -replace '\|', '/'
      $ds = $dist.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
      $out += ($q[0] + '|' + $q[1] + '|' + $q[2] + '|' + $q[4] + '|' + $cc + '|' + $cn + '|' + $city + '|' + $ds + '|' + $ring + '|' + $org)
    }
    $out | Set-Content (Join-Path (Get-DataDir) 'geo.tsv') -Encoding UTF8
    $nhome = @($out | Where-Object { ($_ -split '\|')[4] -eq $hp.cc }).Count
    $nunk = @($out | Where-Object { ($_ -split '\|')[4] -eq '??' }).Count
    Add-Log 'ok' ('гео: ' + $out.Count + ' | дом-страна ' + $hp.cc + ' (отфильтруется в d6): ' + $nhome + ' | гео не ответил: ' + $nunk)
  } }

  6 { Run-Cell 'd' 6 {
    Age-Scores  # v9: старение очков - лидер держится, пока работает ('халиф на час')
    $r = Get-RankedUniversal -GeoTsv 'geo.tsv'
    if ($r.total -eq 0) { Add-Log '!!' 'geo.tsv пуст (координата: d5)'; return }
    $list = @($r.ranked)
    if ($list.Count -eq 0) {
      Add-Log '!!' ('вне дом-страны ' + $r.home.cc + ' живых: 0 | своих отфильтровано: ' + $r.homeN + ' | координата: повторить ряды c и d')
      return
    }
    $rank = 0
    $list = @($list | ForEach-Object { $rank++; $_ | Add-Member NoteProperty rank $rank -Force; $_ })
    $best = $list[0]
    $nbMark = ''
    if ($best.neighbor -eq 1) { $nbMark = ' | СОСЕД' }
    $obj = [ordered]@{
      ts     = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
      policy = 'universal v9: не дом-страна (' + $r.home.cc + '), соседи в хвост, score desc, класс дальности, org cap 2'
      home   = $r.home.cc
      proto  = $best.proto
      ip     = $best.host
      port   = $best.port
      http_s = $best.t
      cc     = $best.cc
      country = $best.country
      city   = $best.city
      dist_km = $best.dist_km
      ring   = $best.ring
      org    = $best.org
      score  = [double]$best.score
      top8   = @($list | Select-Object -First 8 | ForEach-Object { $_.proto + '|' + $_.host + '|' + $_.port + '|' + $_.t + '|' + $_.cc + '|R' + $_.ring + '|' + $_.dist_km + 'km|sc' + [Math]::Round($_.score, 0) })
    }
    $obj | ConvertTo-Json | Set-Content (Join-Path (Get-DataDir) 'best.json') -Encoding UTF8
    $exp = [ordered]@{
      ts     = $obj.ts
      origin = ('дом ' + $r.home.cc + ' ' + $r.home.lat + ',' + $r.home.lon + ' (' + $r.home.src + ')')
      policy = 'не дом-страна; соседи в хвост; score desc; класс дальности; org cap 2'
      count  = $list.Count
      servers = @($list | ForEach-Object {
        [ordered]@{ host = $_.host; port = $_.port; proto = $_.proto; country = $_.country; cc = $_.cc; city = $_.city; dist_km = $_.dist_km; ring = $_.ring; http_s = $_.t; score = [Math]::Round($_.score, 0); neighbor = [int]$_.neighbor; org = $_.org }
      })
    }
    $exp | ConvertTo-Json -Depth 5 | Set-Content (Join-Path (Get-DataDir) 'servers_export.json') -Encoding UTF8
    Add-Log 'ok' ('выбор (универсальный): R' + $best.ring + ' ' + $best.proto + ' ' + $best.host + ':' + $best.port + ' | ' + $best.country + '/' + $best.city + ' | ' + $best.dist_km + ' км от ' + $r.home.cc + ' | score ' + [Math]::Round($best.score, 0) + ' | HTTP-204 за ' + $best.t + ' c' + $nbMark)
    $nbN = @($list | Where-Object { $_.neighbor -eq 1 }).Count
    Add-Log 'i' ('кандидатов: ' + $list.Count + ' (соседей в хвосте: ' + $nbN + ') | своих отфильтровано: ' + $r.homeN + ' | точка отсчёта: ' + $r.home.src)
    Add-Log 'i' ('экспорт с очками для Chrome MV3: data\servers_export.json (' + $list.Count + ' серверов)')
  } }

  7 { Run-Cell 'd' 7 {
    Show-Board
    Show-KeyFacts
  } }

  8 { Run-Cell 'd' 8 {
    $b = Join-Path (Get-DataDir) 'best.json'
    if (-not (Test-Path $b)) { Add-Log 'i' 'аудит: best.json отсутствует (выбор ещё не делался)'; return }
    try {
      $j = Get-Content $b -Raw -Encoding UTF8 | ConvertFrom-Json
      $ageH = [Math]::Round(((Get-Date) - (Get-Item $b).LastWriteTime).TotalHours, 1)
      $geo = ''
      if ($j.PSObject.Properties['ring']) {
        $homeCc = 'RU'
        if ($j.PSObject.Properties['home']) { $homeCc = $j.home }
        $geo = ' | R' + $j.ring + ' ' + $j.cc + ' ' + $j.dist_km + ' км от дома ' + $homeCc
      }
      $sc = ''
      if ($j.PSObject.Properties['score']) { $sc = ' | score ' + $j.score }
      Add-Log 'i' ('аудит выбора: ' + $j.proto + ' ' + $j.ip + ':' + $j.port + $geo + $sc + ' | возраст ' + $ageH + ' ч | топ8: ' + @($j.top8).Count)
      $ef = Join-Path (Get-DataDir) 'servers_export.json'
      if (Test-Path $ef) {
        try {
          $e = Get-Content $ef -Raw -Encoding UTF8 | ConvertFrom-Json
          Add-Log 'i' ('экспорт для Chrome MV3: ' + @($e.servers).Count + ' серверов (data\servers_export.json)')
        } catch {}
      }
      if ($ageH -gt 24) { Add-Log 'i' 'аудит: выбор старше 24ч - координата: повторить ряды c и d' }
    } catch { Add-Log '!!' ('аудит best.json: ' + $_.Exception.Message) }
  } }

  default { Add-Log '??' ('c04_probe: нет клетки ' + $Cell) }
}
