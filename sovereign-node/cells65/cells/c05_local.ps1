# CELL-65 :: c05_local.ps1 - ряд E: ЛОКАЛЬНЫЙ ПРОКСИ на стороне пользователя (e1..e8)
# gost (ginuerzh/gost, GitHub, с 2017 г.) - локальный сервер: 127.0.0.1:18080 HTTP, 18081 SOCKS5,
# цепочкой к выбранному в d6 серверу. Релиз v2.12.0 - zip-архив (проверено при сборке).
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

function Get-GostArch {
  $a = $env:PROCESSOR_ARCHITECTURE
  if ($a -eq 'ARM64') { return 'arm64' }
  if ($a -eq 'x86') { return '386' }
  return 'amd64'
}

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'e' 1 {
    $arch = Get-GostArch
    $api = Join-Path (Get-DataDir) 'gost_release.json'
    $url = ''
    $tag = ''
    $ok = Invoke-HttpGet -Url 'https://api.github.com/repos/ginuerzh/gost/releases/latest' -OutFile $api -TimeoutSec 30
    if ($ok) {
      try {
        $j = Get-Content $api -Raw -Encoding UTF8 | ConvertFrom-Json
        $tag = $j.tag_name
        foreach ($a in $j.assets) {
          if ($a.name -match ('windows_' + $arch + '\.zip$') -or $a.name -match ('windows_' + $arch + 'v3\.zip$')) { $url = $a.browser_download_url; break }
        }
      } catch {}
    }
    if (-not $url) {
      $url = 'https://github.com/ginuerzh/gost/releases/download/v2.12.0/gost_2.12.0_windows_' + $arch + '.zip'
      $tag = 'v2.12.0 (запасная координата)'
    }
    Add-Log 'i' ('gost ' + $tag + ' | arch: ' + $arch + ' | ' + $url)
    $zip = Join-Path (Get-BinDir) 'gost.zip'
    if (-not (Invoke-HttpGet -Url $url -OutFile $zip -TimeoutSec 180)) { Add-Log '!!' 'gost: загрузка не удалась'; return }
    # v8: integrity (пункт внешнего аудита ПРИНЯТ - живая сверка 2026-09-30: checksums.txt
    # у v2.12.0 существует; пин сверен двумя путями). Сверяем zip ДО распаковки;
    # нечем сверить или не совпал - установка отменяется (fail-closed).
    $asset = Split-Path -Leaf $url
    $pin = @{
      'gost_2.12.0_windows_386.zip' = 'F7732F53C1ACAEAEE1265ED7B48250DDC59F713C1D4F93E3DFB73387C4544FD8'
      'gost_2.12.0_windows_amd64.zip' = '2EBE0CB6AC5E966647B222A1F5AC1AE4CE1F340E190F5F69E381C4F694526D43'
      'gost_2.12.0_windows_amd64v3.zip' = '1B320B9D3E607B7BEB40E5315638FC62E8AF961C6B021FFE5EE979AD3A11ABD3'
      'gost_2.12.0_windows_arm64.zip' = '6FA65251F64B498653A25A462BCAA945C4262083814AF77B4077FC9E940B2A2E'
    }
    $expected = ''
    if ($pin.ContainsKey($asset)) { $expected = $pin[$asset] }
    $t = ($tag -split ' ')[0]
    if ($t -match '^v[0-9]') {
      $csFile = Join-Path (Get-BinDir) 'gost_checksums.txt'
      if (Invoke-HttpGet -Url ('https://github.com/ginuerzh/gost/releases/download/' + $t + '/checksums.txt') -OutFile $csFile -TimeoutSec 30) {
        $row = @(Get-Content $csFile -ErrorAction SilentlyContinue | Where-Object { $_ -match ('^[0-9a-fA-F]{64}\s+\*?' + [regex]::Escape($asset) + '\s*$') })
        if ($row.Count -gt 0) { $expected = [regex]::Match($row[0], '^[0-9a-fA-F]{64}').Value.ToUpper() }
      }
    }
    $zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($expected -eq '') { Remove-Item $zip -Force -ErrorAction SilentlyContinue; Add-Log '!!' 'gost: хеш zip нечем сверить (fail-closed) - установка отменена'; return }
    if ($zipHash -ne $expected) { Remove-Item $zip -Force -ErrorAction SilentlyContinue; Add-Log '!!' ('gost: SHA256 НЕ совпал (' + $zipHash.Substring(0, 16) + '... vs ' + $expected.Substring(0, 16) + '...) - установка отменена'); return }
    Add-Log 'ok' ('gost: SHA256 сверен (' + $asset + '): ' + $zipHash.Substring(0, 16) + '...')
    $tmp = Join-Path (Get-BinDir) 'gost_tmp'
    try {
      try { Unblock-File -Path $zip -ErrorAction SilentlyContinue } catch {}
      Expand-Archive -Path $zip -DestinationPath $tmp -Force
      $exe = Get-ChildItem $tmp -Recurse -Filter 'gost.exe' | Select-Object -First 1
      if (-not $exe) { Add-Log '!!' 'gost.exe не найден в архиве'; return }
      Copy-Item $exe.FullName (Join-Path (Get-BinDir) 'gost.exe') -Force
      try { Unblock-File -Path (Join-Path (Get-BinDir) 'gost.exe') -ErrorAction SilentlyContinue } catch {}
      $hash = (Get-FileHash (Join-Path (Get-BinDir) 'gost.exe') -Algorithm SHA256).Hash
      Add-Log 'ok' ('gost.exe готов | sha256: ' + $hash.Substring(0, 16) + '...')
      try {
        $v = & (Join-Path (Get-BinDir) 'gost.exe') -V 2>$null
        Add-Log 'i' ('gost -V: ' + ($v -join ' '))
      } catch { Add-Log 'i' 'gost -V: не ответил (возможен флаг антивируса - координата в README)' }
    } catch { Add-Log '!!' ('распаковка: ' + $_.Exception.Message) }
  } }

  2 { Run-Cell 'e' 2 {
    $b = Join-Path (Get-DataDir) 'best.json'
    if (-not (Test-Path $b)) { Add-Log '!!' 'best.json нет (координата: d6)'; return }
    try { $best = Get-Content $b -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Log '!!' 'best.json битый'; return }
    # v8: валидация полей (аудит: инъекция через best.json). proto - только набор d6,
    # ip - без пробелов/кавычек/@, порт - число 1..65535; запись атомарная.
    if (@('http', 'socks4', 'socks5') -notcontains [string]$best.proto) { Add-Log '!!' ('best.json: протокол вне набора: ' + $best.proto); return }
    $ip = [string]$best.ip
    if ($ip -notmatch '^[0-9A-Za-z\.\-]+$') { Add-Log '!!' 'best.json: ip вне формата (пробелы/кавычки/@ недопустимы)'; return }
    $port = 0
    if (-not [int]::TryParse([string]$best.port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { Add-Log '!!' 'best.json: порт вне 1..65535'; return }
    $up = $best.proto + '://' + $ip + ':' + $port
    $ga = '-L "http://127.0.0.1:18080" -L "socks5://127.0.0.1:18081" -F "' + $up + '"'
    $af = Join-Path (Get-DataDir) 'gost_args.txt'
    Set-Content ($af + '.tmp') $ga -Encoding UTF8
    Move-Item ($af + '.tmp') $af -Force
    Add-Log 'ok' ('конфиг: локаль 18080 (HTTP) + 18081 (SOCKS5) -> ' + $up)
  } }

  3 { Run-Cell 'e' 3 {
    $exe = Join-Path (Get-BinDir) 'gost.exe'
    if (-not (Test-Path $exe)) { Add-Log '!!' 'gost.exe нет (координата: e1)'; return }
    $af = Join-Path (Get-DataDir) 'gost_args.txt'
    if (-not (Test-Path $af)) { Add-Log '!!' 'gost_args.txt нет (координата: e2)'; return }
    # v8: проверяются ОБА порта (аудит: 18081 мог остаться за чужим процессом)
    $busy = @(); $mineBoth = $true
    foreach ($p in @(18080, 18081)) {
      $lst = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
      if (-not $lst) { $mineBoth = $false; continue }
      $pr = Get-Process -Id $lst.OwningProcess -ErrorAction SilentlyContinue
      if ($pr -and $pr.ProcessName -eq 'gost') { $busy += $p } else { Add-Log '!!' ('порт ' + $p + ' занят процессом ' + $pr.ProcessName + ' (координата: освободить порт)'); return }
    }
    if ($busy.Count -eq 2) { Add-Log 'i' 'gost уже слушает 18080 и 18081 - старт не нужен'; return }
    if ($busy.Count -eq 1) { Add-Log '!!' ('gost слушает только ' + $busy[0] + ' - половинчатое состояние (координата: e6 перезапуск)'); return }
    $ga = (Get-Content $af -Raw).Trim()
    try {
      $p = Start-Process -FilePath $exe -ArgumentList $ga -WindowStyle Hidden -WorkingDirectory (Get-BinDir) -RedirectStandardOutput (Join-Path (Get-BinDir) 'gost_out.log') -RedirectStandardError (Join-Path (Get-BinDir) 'gost_err.log') -PassThru
      Start-Sleep -Seconds 2
      if ($p.HasExited) { Add-Log '!!' ('gost завершился сразу, код ' + $p.ExitCode + ' (bin\gost_err.log)'); return }
      Set-Content (Join-Path (Get-DataDir) 'gost.pid') ([string]$p.Id) -Encoding ASCII
      Add-Log 'ok' ('gost запущен, PID ' + $p.Id + ' (записан gost.pid)')
    } catch { Add-Log '!!' ('старт gost: ' + $_.Exception.Message) }
  } }

  4 { Run-Cell 'e' 4 {
    $okH = Test-HttpViaProxy -Ip '127.0.0.1' -Port 18080 -Proto 'http'
    $okS = Test-HttpViaProxy -Ip '127.0.0.1' -Port 18081 -Proto 'socks5'
    # v9: меритократия - здоровье лидера меняет его очки (+10 / x0.3)
    $bkey = ''
    $bf9 = Join-Path (Get-DataDir) 'best.json'
    if (Test-Path $bf9) {
      try { $bb9 = Get-Content $bf9 -Raw -Encoding UTF8 | ConvertFrom-Json; $bkey = $bb9.proto + '|' + $bb9.ip + '|' + $bb9.port } catch {}
    }
    if (-not $okH) {
      # v7: прогрев. Холодный socks5-upstream отвечает через 10-20 с (живой факт 6ORMAN:
      # HTTP нет 204 на 11-й секунде, 204 на 31-й). Один повтор перед вердиктом.
      Add-Log 'i' 'здоровье: HTTP нет 204 - прогрев upstream, повтор через 4 с'
      Start-Sleep -Seconds 4
      $okH = Test-HttpViaProxy -Ip '127.0.0.1' -Port 18080 -Proto 'http'
      if ($okH) { Add-Log 'i' 'здоровье: 204 со второй попытки (upstream прогрелся)' }
    }
    if ($okH) {
      # v10: 204 мало - прозрачные фейки отдают 204 БЕЗ реального интернета
      # ("подключаемся к серверу без доступа в интернет" - живая жалоба 6ORMAN)
      if (Test-RealViaProxy -Ip '127.0.0.1' -Port 18080 -TimeoutSec 8) {
        Set-Flag 'gost_ok' '1'; Add-Log 'ok' 'здоровье: HTTP 127.0.0.1:18080 -> 204 + реальный трафик OK'
        if ($bkey -ne '') { $sc = Update-Score -Key $bkey -Delta 10; Add-Log 'i' ('меритократия: лидер +10 (score ' + $sc + ')') }
      } else {
        Set-Flag 'gost_ok' '0'; Add-Log '!!' 'здоровье: 204 есть, но реальный трафик (msftconnecttest) НЕ проходит - upstream полуживой (координата: e7 смена upstream)'
        if ($bkey -ne '') { $sc = Update-Score -Key $bkey -Mult 0.3; Add-Log 'i' ('меритократия: лидер понижен x0.3 (score ' + $sc + ') - его место займёт следующий по очкам') }
      }
    } else {
      Set-Flag 'gost_ok' '0'; Add-Log '!!' 'здоровье: HTTP 127.0.0.1:18080 -> нет 204 и на повторе (координата: e7 смена upstream)'
      if ($bkey -ne '') { $sc = Update-Score -Key $bkey -Mult 0.3; Add-Log 'i' ('меритократия: лидер понижен x0.3 (score ' + $sc + ') - его место займёт следующий по очкам') }
    }
    if ($okS) { Add-Log 'ok' 'здоровье: SOCKS5 127.0.0.1:18081 -> 204' }
    else { Add-Log 'i' 'здоровье: SOCKS5 127.0.0.1:18081 -> нет 204' }
    $b = Join-Path (Get-DataDir) 'best.json'
    if (Test-Path $b) {
      try { $best = Get-Content $b -Raw -Encoding UTF8 | ConvertFrom-Json; Add-Log 'i' ('upstream: ' + $best.proto + ' ' + $best.ip + ':' + $best.port) } catch {}
    }
  } }

  5 { Run-Cell 'e' 5 {
    $exeP = (Join-Path (Get-BinDir) 'gost.exe').ToLower()
    $g = @(Get-Process -Name gost -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.ToLower() -eq $exeP })
    if ($g.Count -eq 0) { $g = $null }  # v8: чужой gost с тем же именем не выдаётся за наш (аудит)
    if ($g) { Add-Log 'i' ('процесс gost: PID ' + ($g.Id -join ', ') + ' | память: ' + [Math]::Round(($g | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1) + ' МБ') }
    else { Add-Log 'i' 'процесс gost: не запущен' }
    foreach ($p in @(18080, 18081)) {
      $cn = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($cn) { Add-Log 'ok' ('слушает: ' + $p + ' (PID ' + $cn.OwningProcess + ')') }
      else { Add-Log 'i' ('не слушает: ' + $p) }
    }
  } }

  6 { Run-Cell 'e' 6 {
    # v7: честный факт; v8 (аудит): слепой Stop-Process -Name удалён - гасим только СВОЙ
    # экземпляр: gost.pid -> владелец 18080/18081; мягко, затем принудительно.
    $target = $null
    $pidFile = Join-Path (Get-DataDir) 'gost.pid'
    if (Test-Path $pidFile) {
      try { $saved = [int](Get-Content $pidFile -Raw).Trim() } catch { $saved = 0 }
      $pr = Get-Process -Id $saved -ErrorAction SilentlyContinue
      if ($pr -and $pr.ProcessName -eq 'gost') { $target = $pr }
    }
    if (-not $target) {
      foreach ($p in @(18080, 18081)) {
        $lst = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($lst) { $pr = Get-Process -Id $lst.OwningProcess -ErrorAction SilentlyContinue; if ($pr -and $pr.ProcessName -eq 'gost') { $target = $pr; break } }
      }
    }
    if ($target) {
      Add-Log 'i' ('остановка gost: PID ' + $target.Id)
      try { Stop-Process -Id $target.Id -ErrorAction SilentlyContinue; try { Wait-Process -Id $target.Id -Timeout 3 -ErrorAction SilentlyContinue } catch {} } catch {}
      if (Get-Process -Id $target.Id -ErrorAction SilentlyContinue) { try { Stop-Process -Id $target.Id -Force -ErrorAction SilentlyContinue } catch {}; Add-Log 'i' 'gost не вышел мягко - снят принудительно' }
      Add-Log 'ok' 'gost остановлен'
      Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    } else { Add-Log 'i' 'gost не был запущен - останавливать нечего' }
    $freed = $false
    for ($i = 0; $i -lt 10; $i++) {
      $l1 = Get-NetTCPConnection -LocalPort 18080 -State Listen -ErrorAction SilentlyContinue
      $l2 = Get-NetTCPConnection -LocalPort 18081 -State Listen -ErrorAction SilentlyContinue
      if (-not $l1 -and -not $l2) { $freed = $true; break }
      Start-Sleep -Milliseconds 500
    }
    if (-not $freed) { Add-Log 'i' 'порты 18080/18081 ещё заняты - старт может не связаться' }
    & $PSCommandPath -Cell 3
    & $PSCommandPath -Cell 4
  } }

  7 { Run-Cell 'e' 7 {
    $b = Join-Path (Get-DataDir) 'best.json'
    $gf = Join-Path (Get-DataDir) 'geo.tsv'
    $hf = Join-Path (Get-DataDir) 'http_ok.tsv'
    $cands = @()
    $src = ''
    $scoreMap = Get-ScoreMap
    $homeCc = (Get-HomePoint).cc
    if (Test-Path $gf) {
      $src = 'geo'
      # v9: меритократия - сортировка (score desc, класс дальности, время); мусорная строка не роняет выборку
      $cands = @(Get-Content $gf | Where-Object {
        $f = $_ -split '\|'
        ($f.Count -ge 9) -and ($f[4] -ne $homeCc) -and ($f[8] -match '^\d+$') -and ($f[3] -match '^[0-9]+\.?[0-9]*$')
      } | ForEach-Object {
        $f = $_ -split '\|'
        $k9 = $f[0] + '|' + $f[1] + '|' + $f[2]
        $sc9 = 50.0
        if ($scoreMap.ContainsKey($k9)) { $sc9 = $scoreMap[$k9] }
        New-Object PSObject -Property @{ line = $_; key = $k9; score = $sc9; ring = [int]$f[8]; t = [double]$f[3] }
      } | Sort-Object -Property @{e='score';Descending=$true}, @{e='ring';Descending=$false}, @{e='t';Descending=$false})
    } elseif (Test-Path $hf) {
      $src = 'http'
      # v10: вердикт пробы важнее времени (OK3 -> OK2 -> OK1): узлы, прошедшие все
      # три цели, идут первыми; "быстрые" 204-фейки уходят в хвост
      $cands = @(Get-Content $hf | Where-Object {
        $f = $_ -split '\|'
        ($f.Count -ge 5) -and ($f[3] -match '^OK') -and ($f[4] -match '^[0-9]+\.?[0-9]*$')
      } | ForEach-Object {
        $f = $_ -split '\|'
        $vr = 2
        if ($f[3] -eq 'OK3') { $vr = 0 } elseif ($f[3] -eq 'OK2') { $vr = 1 }
        New-Object PSObject -Property @{ line = $_; key = ($f[0] + '|' + $f[1] + '|' + $f[2]); score = 50.0; vr = $vr; t = [double]$f[4] }
      } | Sort-Object -Property vr, t)
    } else { Add-Log '!!' 'нет ни geo.tsv, ни http_ok.tsv (координата: ряд d)'; return }
    $cur = ''
    if (Test-Path $b) { try { $j = Get-Content $b -Raw -Encoding UTF8 | ConvertFrom-Json; $cur = $j.proto + '|' + $j.ip + '|' + $j.port } catch {} }
    # v10: карантин - узел с потерянным здоровьем НЕ выбирается повторно 30 минут
    # ("в ЖИЗНЬ второй раз подключаешься к тому, что не работало" - живая жалоба 6ORMAN)
    $cd = Join-Path (Get-DataDir) 'cooldown.tsv'
    $recent = @{}
    if (Test-Path $cd) {
      $cut = (Get-Date).AddMinutes(-30)
      foreach ($lc in @(Get-Content $cd -ErrorAction SilentlyContinue | Select-Object -Last 400)) {
        $fc = $lc -split '\|'
        if ($fc.Count -lt 2) { continue }
        $dtc = New-Object DateTime 2000,1,1
        # v10: ключ сам содержит '|' (proto|ip|port) - дата всегда ПОСЛЕДНЕЕ поле,
        # ключ = всё слева от него (урок v8/v9: ключ с '|' не должен ломать парсер)
        $dstr = $fc[$fc.Count - 1]
        $ckey2 = ($fc[0..($fc.Count - 2)]) -join '|'
        if ([DateTime]::TryParse($dstr, [ref]$dtc) -and $dtc -gt $cut) { $recent[$ckey2] = 1 }
      }
    }
    if ($cur -ne '') {
      Add-Content -Path $cd -Value ($cur + '|' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
      $recent[$cur] = 1
      Add-Log 'i' ('карантин 30 мин на ' + $cur + ' (здоровье потеряно)')
    }
    if ($recent.Count -gt 0) {
      $kept = @($cands | Where-Object { -not $recent.ContainsKey($_.key) })
      if ($kept.Count -gt 0) { $cands = $kept }
      else { Add-Log 'i' 'все кандидаты в карантине - использую полный список (лучше попытка, чем простой)' }
    }
    $next = $null
    $started = $false
    foreach ($c in $cands) {
      $ckey = $c.key
      if ($ckey -eq $cur) { $started = $true; continue }
      if ($cur -eq '' -or $started) { $next = $c; break }
    }
    if (-not $next -and $cands.Count -gt 0) {
      # v10: текущего upstream нет среди живых (проба его не подтвердила) -
      # НЕ остаёмся на нём, берём первого проверенного из списка
      $next = $cands[0]
      Add-Log 'i' ('текущего upstream нет среди живых пробы - беру первого проверенного: ' + $next.key)
    }
    if (-not $next) { Add-Log '!!' 'запасных кандидатов нет (координата: ряд d заново)'; return }
    $nextLine = ''; $nextSc = 50.0
    $nextLine = $next.line; $nextSc = $next.score
    $q = $nextLine -split '\|'
    $obj = [ordered]@{ ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); proto = $q[0]; ip = $q[1]; port = $q[2] }
    $mark = ''
    if ($src -eq 'geo') {
      $obj['http_s'] = $q[3]
      $obj['cc'] = $q[4]; $obj['country'] = $q[5]; $obj['city'] = $q[6]; $obj['dist_km'] = $q[7]; $obj['ring'] = $q[8]
      $obj['top8'] = @()
      $mark = 'R' + $q[8] + ' (' + $q[5] + '/' + $q[6] + ', ' + $q[7] + ' км) '
    } else {
      $obj['http_s'] = $q[4]
      $obj['top8'] = @()
    }
    $obj | ConvertTo-Json | Set-Content ($b + '.tmp') -Encoding UTF8
    Move-Item ($b + '.tmp') $b -Force  # v8: атомарная запись best.json (аудит)
    Add-Log 'ok' ('upstream сменён на: ' + $mark + $q[0] + ' ' + $q[1] + ':' + $q[2] + ' | score ' + [Math]::Round($nextSc, 0) + ' | порядок: ' + $(if ($src -eq 'geo') { 'меритократия (score desc), не дом-страна ' + $homeCc } else { 'по времени (запасной)' }))
    & $PSCommandPath -Cell 2
    & $PSCommandPath -Cell 6
  } }

  8 { Run-Cell 'e' 8 {
    foreach ($f in @('gost_out.log', 'gost_err.log')) {
      $p = Join-Path (Get-BinDir) $f
      if (Test-Path $p) {
        Add-Log 'i' ('--- bin\' + $f + ' (последние 10 строк) ---')
        Get-Content $p -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Add-Log 'i' ('  ' + $_) }
      } else { Add-Log 'i' ('bin\' + $f + ': пока пусто') }
    }
  } }

  default { Add-Log '??' ('c05_local: нет клетки ' + $Cell) }
}
