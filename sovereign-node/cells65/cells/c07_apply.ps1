# CELL-65 :: c07_apply.ps1 - ряд G: СИСТЕМНЫЙ ПРОКСИ Windows (g1..g8)
# HKCU Internet Settings + уведомление WinInet. Всегда бэкап до изменения, откат g3.
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

$script:ProxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'g' 1 {
    $bf = Join-Path (Get-DataDir) 'proxy_backup.json'
    if (Test-Path $bf) { Add-Log 'i' 'бэкап уже есть - не перезаписываю (откат: g3 вернёт исходное)'; return }
    $v = Get-ItemProperty $script:ProxyKey -ErrorAction SilentlyContinue
    $b = [ordered]@{
      ts            = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
      ProxyEnable   = 0
      ProxyServer   = ''
      AutoConfigURL = ''
    }
    if ($v) {
      if ($null -ne $v.ProxyEnable) { $b.ProxyEnable = [int]$v.ProxyEnable }
      if ($null -ne $v.ProxyServer) { $b.ProxyServer = [string]$v.ProxyServer }
      if ($null -ne $v.AutoConfigURL) { $b.AutoConfigURL = [string]$v.AutoConfigURL }
    }
    $b | ConvertTo-Json | Set-Content $bf -Encoding UTF8
    Add-Log 'ok' ('бэкап прокси-настроек сохранён: ' + ($b | ConvertTo-Json -Compress))
  } }

  2 { Run-Cell 'g' 2 {
    $exe = Join-Path (Get-BinDir) 'gost.exe'
    if (-not (Test-Path $exe)) { Add-Log '!!' 'gost нет (координата: e1)'; return }
    if (-not (Test-HttpViaProxy -Ip '127.0.0.1' -Port 18080 -Proto 'http')) { Add-Log '!!' 'локальный прокси не отвечает (координата: e3/e4)'; return }
    $v = Get-ItemProperty $script:ProxyKey -ErrorAction SilentlyContinue
    if ($v -and $v.AutoConfigURL) { Add-Log '!!' ('AutoConfigURL активен (' + $v.AutoConfigURL + ') - PAC перебивает ручной прокси; координата: убрать PAC'); return }
    $bf = Join-Path (Get-DataDir) 'proxy_backup.json'
    if (-not (Test-Path $bf)) { & $PSCommandPath -Cell 1 }
    Set-ItemProperty $script:ProxyKey -Name ProxyEnable -Value 1 -Type DWord
    Set-ItemProperty $script:ProxyKey -Name ProxyServer -Value '127.0.0.1:18080' -Type String
    $po = 'localhost;127.*;192.168.*;10.*;<local>'
    $exf = Join-Path (Get-DataDir) 'exclude.txt'
    if (Test-Path $exf) {
      $ex = @(Get-Content $exf | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
      if ($ex.Count -gt 0) { $po = $po + ';' + ($ex -join ';') }
    }
    Set-ItemProperty $script:ProxyKey -Name ProxyOverride -Value $po -Type String
    [void](Invoke-WinInetRefresh)
    Set-Flag 'proxy_applied' '1'
    Add-Log 'ok' 'системный прокси: ВКЛ 127.0.0.1:18080 (исключения: локальные адреса + exclude.txt)'
    Add-Log 'i' 'факт: часть программ читает прокси только при своём старте - перезапусти браузер'
  } }

  3 { Run-Cell 'g' 3 {
    $bf = Join-Path (Get-DataDir) 'proxy_backup.json'
    if (-not (Test-Path $bf)) {
      Set-ItemProperty $script:ProxyKey -Name ProxyEnable -Value 0 -Type DWord
      [void](Invoke-WinInetRefresh)
      Add-Log 'ok' 'бэкапа не было - ProxyEnable=0 выставлен (координата: g5 покажет текущее)'
      return
    }
    try {
      $b = Get-Content $bf -Raw -Encoding UTF8 | ConvertFrom-Json
      Set-ItemProperty $script:ProxyKey -Name ProxyEnable -Value ([int]$b.ProxyEnable) -Type DWord
      if ($b.ProxyServer) { Set-ItemProperty $script:ProxyKey -Name ProxyServer -Value $b.ProxyServer -Type String }
      else { Remove-ItemProperty $script:ProxyKey -Name ProxyServer -ErrorAction SilentlyContinue }
      if ($b.AutoConfigURL) { Set-ItemProperty $script:ProxyKey -Name AutoConfigURL -Value $b.AutoConfigURL -Type String }
      [void](Invoke-WinInetRefresh)
      Set-Flag 'proxy_applied' '0'
      Add-Log 'ok' ('восстановлено из бэкапа: ProxyEnable=' + $b.ProxyEnable + ' ProxyServer=' + $b.ProxyServer)
    } catch { Add-Log '!!' ('откат: ' + $_.Exception.Message) }
  } }

  4 { Run-Cell 'g' 4 {
    $v = Get-ItemProperty $script:ProxyKey -ErrorAction SilentlyContinue
    if ($v) {
      Add-Log 'i' ('ProxyEnable=' + $v.ProxyEnable + ' | ProxyServer=' + $v.ProxyServer + ' | AutoConfigURL=' + $v.AutoConfigURL)
      Add-Log 'i' ('ProxyOverride=' + $v.ProxyOverride)
    }
  } }

  5 { Run-Cell 'g' 5 {
    $c = Get-Curl
    if (-not $c) { Add-Log '!!' 'curl нет'; return }
    $t = (& $c -s -o NUL --max-time 10 -x 'http://127.0.0.1:18080' -w '%{http_code}' 'http://www.gstatic.com/generate_204' 2>$null)
    Add-Log 'i' ('через локальный прокси 18080: код ' + $t)
    $ip = (& $c -s --max-time 12 -x 'http://127.0.0.1:18080' 'https://api.ipify.org' 2>$null)
    if ($ip) { Add-Log 'i' ('выходной IP через прокси: ' + $ip) } else { Add-Log 'i' 'выходной IP через прокси: не получен' }
    $g = Get-GeoFact
    if ($g -and $g.query) { Add-Log 'i' ('прямой выходной IP: ' + $g.query + ' (' + $g.countryCode + ')') }
  } }

  6 { Run-Cell 'g' 6 {
    try {
      $o = (& "$env:SystemRoot\System32\netsh.exe" winhttp show proxy 2>&1) | Out-String
      $o = $o.Trim()
      if ($o -match '[╔╤]') {
        try { $b866 = [Text.Encoding]::GetEncoding(866).GetBytes($o); $t2 = [Text.Encoding]::UTF8.GetString($b866); if (-not $t2.Contains([char]0xFFFD)) { $o = $t2 } } catch {}
      }
      $srv = ''
      if ($o -match '(\d{1,3}\.){3}\d{1,3}(:\d+)?') { $srv = $Matches[0] }
      if ($srv) { Add-Log 'i' ('winhttp (факт): прокси-сервер ' + $srv + ' (меняется только админом - CELL-65 системный winhttp не меняет)') }
      elseif ($o -match 'Прямой|Direct access') { Add-Log 'i' 'winhttp (факт): прямой доступ (без прокси-сервера); CELL-65 системный winhttp не меняет' }
      else { $flat = ($o -replace '\s+', ' '); if ($flat.Length -gt 120) { $flat = $flat.Substring(0, 120) }; Add-Log 'i' ('winhttp (факт): ' + $flat) }
    } catch { Add-Log 'i' 'winhttp: нет данных' }
  } }

  7 { Run-Cell 'g' 7 {
    $exf = Join-Path (Get-DataDir) 'exclude.txt'
    if (-not (Test-Path $exf)) { Set-Content $exf '' -Encoding UTF8; Add-Log 'ok' ('создан ' + $exf + ' - пиши по одному шаблону в строку, напр. *.local или 192.168.1.*') }
    else { Add-Log 'i' ('exclude.txt уже есть: ' + $exf) }
    $v = Get-ItemProperty $script:ProxyKey -ErrorAction SilentlyContinue
    if ($v -and [int]$v.ProxyEnable -eq 1) {
      $null = & $PSCommandPath -Cell 2
      Add-Log 'ok' 'исключения переприменены'
    } else { Add-Log 'i' 'системный прокси выключен - исключения применятся при g2' }
  } }

  8 { Run-Cell 'g' 8 {
    Ensure-Dirs
    $p = Join-Path (Get-DataDir) 'proxy_report.txt'
    $v = Get-ItemProperty $script:ProxyKey -ErrorAction SilentlyContinue
    $b = Get-Content (Join-Path (Get-DataDir) 'proxy_backup.json') -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    $lines = @()
    $lines += ('CELL-65 прокси-отчёт ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $lines += ('текущее: ProxyEnable=' + $v.ProxyEnable + ' ProxyServer=' + $v.ProxyServer)
    $lines += ('Override: ' + $v.ProxyOverride)
    $lines += ('PAC: ' + $v.AutoConfigURL)
    $lines += 'бэкап: ' + $b
    $lines | Set-Content $p -Encoding UTF8
    Add-Log 'ok' ('отчёт -> ' + $p)
  } }

  default { Add-Log '??' ('c07_apply: нет клетки ' + $Cell) }
}
