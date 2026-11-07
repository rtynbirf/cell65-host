# CELL-65 :: c02_net.ps1 - ряд B: СЕТЬ (клетки b1..b8)
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'b' 1 {
    try {
      $ads = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
      if ($ads) {
        foreach ($a in $ads) { Add-Log 'i' ('адаптер: ' + $a.Name + ' | ' + $a.InterfaceDescription + ' | ' + $a.LinkSpeed) }
      } else { Add-Log '!!' 'активных адаптеров: 0' }
    } catch { Add-Log '!!' ('Get-NetAdapter: ' + $_.Exception.Message) }
  } }

  2 { Run-Cell 'b' 2 {
    try {
      $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 }
      foreach ($d in $dns) { Add-Log 'i' ('DNS: ' + $d.InterfaceAlias + ' -> ' + ($d.ServerAddresses -join ', ')) }
    } catch { Add-Log '!!' ('DNS: ' + $_.Exception.Message) }
  } }

  3 { Run-Cell 'b' 3 {
    try {
      $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 3
      foreach ($x in $r) { Add-Log 'i' ('маршрут 0.0.0.0/0: via ' + $x.NextHop + ' | if: ' + $x.InterfaceAlias + ' | metric: ' + $x.RouteMetric) }
    } catch { Add-Log '!!' ('маршруты: ' + $_.Exception.Message) }
  } }

  4 { Run-Cell 'b' 4 {
    $g = Get-GeoFact
    if ($g -and $g.status -eq 'success') {
      Add-Log 'i' ('выходной IP: ' + $g.query + ' | ' + $g.country + ' (' + $g.countryCode + ') | ' + $g.isp)
      Add-Log 'i' ('as: ' + $g.as + ' | флаги ip-api: proxy=' + $g.proxy + ' hosting=' + $g.hosting)
      Add-Log 'i' 'ip-api.com: http, без ключа (бесплатный уровень ~45 запросов/мин) - факт'
    } else { Add-Log '!!' 'ip-api: нет ответа (координата: интернет/firewall)' }
  } }

  5 { Run-Cell 'b' 5 {
    try {
      $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
      $p = Get-ItemProperty $k -ErrorAction SilentlyContinue
      if ($p -and $null -ne $p.EnableAutoDoh) { Add-Log 'i' ('DoH (система): EnableAutoDoh=' + $p.EnableAutoDoh) }
      else { Add-Log 'i' 'DoH (система): ключ EnableAutoDoh не задан (значение по умолчанию)' }
    } catch { Add-Log 'i' 'DoH: нет данных' }
  } }

  6 { Run-Cell 'b' 6 {
    foreach ($p in @(18080, 18081)) {
      $free = $true
      try {
        $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p)
        $l.Start(); $l.Stop()
      } catch { $free = $false }
      if ($free) { Add-Log 'ok' ('порт ' + $p + ': свободен') }
      else {
        $who = '?'
        try {
          $cn = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
          if ($cn) { $pr = Get-Process -Id $cn.OwningProcess -ErrorAction SilentlyContinue; if ($pr) { $who = $pr.ProcessName } }
        } catch {}
        Add-Log 'i' ('порт ' + $p + ': занят (' + $who + ')')
      }
    }
  } }

  7 { Run-Cell 'b' 7 {
    foreach ($t in @(@('1.1.1.1', 443), @('8.8.8.8', 443), @('77.88.8.8', 443))) {
      $ms = @()
      for ($i = 0; $i -lt 3; $i++) {
        $m = Test-TcpMs -Ip $t[0] -Port $t[1] -TimeoutMs 1500
        if ($m -ge 0) { $ms += $m }
        Start-Sleep -Milliseconds 200
      }
      if ($ms.Count -gt 0) {
        $ms = @($ms | Sort-Object)
        Add-Log 'i' ('база ' + $t[0] + ':' + $t[1] + ' -> медиана ' + $ms[[int](($ms.Count - 1) / 2)] + ' мс (n=' + $ms.Count + ')')
      } else { Add-Log '!!' ('база ' + $t[0] + ':' + $t[1] + ' -> нет ответа') }
    }
  } }

  8 { Run-Cell 'b' 8 {
    Add-Log 'i' ('время: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' локаль | UTC: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
    $g = Get-GeoFact
    if ($g -and $g.status -eq 'success') { Set-Flag 'geo_home' ($g.countryCode + '/' + $g.city) }
  } }

  default { Add-Log '??' ('c02_net: нет клетки ' + $Cell) }
}
