# CELL-65 :: c06_vpn.ps1 - ряд F: ВСТРОЕННЫЙ VPN-КЛИЕНТ WINDOWS (f1..f8)
# Факт: VPN-клиент - часть самой системы (служба RasMan, Параметры -> Сеть -> VPN;
# rasdial.exe, Add-VpnConnection). В Windows 11 26H1/Home это работает так же -
# встроенный механизм, никаких сторонних VPN-клиентов CELL-65 не ставит.
# Профиль создаётся ТОЛЬКО по твоим данным (свой сервер/учётка) - data\vpn.json.
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'f' 1 {
    foreach ($s in @('RasMan', 'SstpSvc', 'iphlpsvc')) {
      try {
        $svc = Get-Service -Name $s -ErrorAction Stop
        Add-Log 'i' ('служба ' + $s + ': ' + $svc.Status + ' (' + $svc.DisplayName + ')')
      } catch { Add-Log 'i' ('служба ' + $s + ': нет данных') }
    }
    try {
      $vcs = Get-VpnConnection -ErrorAction Stop
      if ($vcs) {
        foreach ($v in $vcs) { Add-Log 'i' ('профиль: ' + $v.Name + ' | ' + $v.ServerAddress + ' | ' + $v.TunnelType + ' | ' + $v.ConnectionStatus) }
      } else { Add-Log 'i' 'профилей VPN: 0' }
    } catch { Add-Log 'i' 'Get-VpnConnection: нет данных' }
    try {
      $rd = (& rasdial 2>&1) -join ' | '
      if ($rd) { Add-Log 'i' ('rasdial: ' + $rd) } else { Add-Log 'i' 'rasdial: активных подключений нет' }
    } catch { Add-Log 'i' 'rasdial: нет данных' }
    try {
      $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
      Add-Log 'i' ('система: ' + $cv.DisplayVersion + ' build ' + $cv.CurrentBuildNumber + '.' + $cv.UBR + ' - VPN-клиент встроен, управляется через Параметры -> Сеть -> VPN')
    } catch {}
  } }

  2 { Run-Cell 'f' 2 {
    $vf = Join-Path (Get-DataDir) 'vpn.json'
    if (-not (Test-Path $vf)) {
      Add-Log '!!' 'data\vpn.json нет. Шаблон - клетка f8 или README. VPN используется с СВОИМ сервером и учёткой'
      return
    }
    try { $v = Get-Content $vf -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Log '!!' ('vpn.json битый: ' + $_.Exception.Message); return }
    if (-not $v.server) { Add-Log '!!' 'vpn.json: server пуст'; return }
    $name = 'CELL65-VPN'
    if ($v.name) { $name = $v.name }
    $tt = 'IKEv2'
    if ($v.type) { $tt = $v.type }
    $pAdd = @{ Name = $name; ServerAddress = $v.server; TunnelType = $tt; RememberCredential = $true }
    if ($tt -eq 'L2TP' -and $v.psk) { $pAdd['L2tpPsk'] = $v.psk }
    try {
      Add-VpnConnection @pAdd
      Add-Log 'ok' ('профиль создан: ' + $name + ' | ' + $tt + ' | ' + $v.server + ' (встроенный клиент, без сторонних программ)')
    } catch { Add-Log '!!' ('Add-VpnConnection: ' + $_.Exception.Message) }
  } }

  3 { Run-Cell 'f' 3 {
    $vf = Join-Path (Get-DataDir) 'vpn.json'
    if (-not (Test-Path $vf)) { Add-Log '!!' 'data\vpn.json нет (координата: f8)'; return }
    try { $v = Get-Content $vf -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Add-Log '!!' 'vpn.json битый'; return }
    $name = 'CELL65-VPN'
    if ($v.name) { $name = $v.name }
    try {
      $o = & rasdial $name $v.user $v.pass 2>&1
      Add-Log 'i' ('rasdial: ' + (($o | Out-String).Trim()))
    } catch { Add-Log '!!' ('rasdial: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 2
    & $PSCommandPath -Cell 5
  } }

  4 { Run-Cell 'f' 4 {
    $vf = Join-Path (Get-DataDir) 'vpn.json'
    $name = 'CELL65-VPN'
    if (Test-Path $vf) { try { $v = Get-Content $vf -Raw -Encoding UTF8 | ConvertFrom-Json; if ($v.name) { $name = $v.name } } catch {} }
    try {
      $o = & rasdial $name /disconnect 2>&1
      Add-Log 'ok' ('rasdial: ' + (($o | Out-String).Trim()))
    } catch { Add-Log '!!' ('rasdial disconnect: ' + $_.Exception.Message) }
  } }

  5 { Run-Cell 'f' 5 {
    try {
      $rd = (& rasdial 2>&1) -join ' | '
      if ($rd) { Add-Log 'i' ('активные: ' + $rd) } else { Add-Log 'i' 'активных VPN: нет' }
    } catch {}
    try {
      $vcs = Get-VpnConnection -ErrorAction SilentlyContinue
      foreach ($v in $vcs) { Add-Log 'i' ('профиль: ' + $v.Name + ' | статус: ' + $v.ConnectionStatus) }
    } catch {}
    try {
      $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 5
      foreach ($x in $r) { Add-Log 'i' ('маршрут: via ' + $x.NextHop + ' | if: ' + $x.InterfaceAlias + ' | metric: ' + $x.RouteMetric) }
    } catch {}
  } }

  6 { Run-Cell 'f' 6 {
    try {
      $vcs = Get-VpnConnection -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'CELL65-*' }
      if ($vcs) {
        foreach ($v in $vcs) {
          try { Remove-VpnConnection -Name $v.Name -Force; Add-Log 'ok' ('свой артефакт снят: профиль ' + $v.Name) } catch { Add-Log '!!' ('Remove-VpnConnection: ' + $_.Exception.Message) }
        }
      } else { Add-Log 'i' 'профилей CELL65-* нет' }
    } catch { Add-Log '!!' ('f6: ' + $_.Exception.Message) }
  } }

  7 { Run-Cell 'f' 7 {
    Add-Log 'i' 'ФАКТЫ о встроенном VPN:'
    Add-Log 'i' ' - VPN-клиент - часть Windows (службы RasMan/SstpSvc; rasdial.exe; командлеты *-VpnConnection)'
    Add-Log 'i' ' - узел: Параметры -> Сеть и Интернет -> VPN (присутствует и в Home-редакции)'
    Add-Log 'i' ' - типы туннеля, которые принимает клиент: IKEv2, SSTP, L2TP/IPsec, PPTP (устарел)'
    Add-Log 'i' ' - публичные списки прокси (ряд c) - это НЕ VPN: у бесплатных серверов нет VPN-протокола и учёток'
    Add-Log 'i' ' - VPN-путь CELL-65 = твой собственный сервер/учётка провайдера/роутера (f2 -> f3)'
    Add-Log 'i' ' - сторонние VPN-клиенты CELL-65 не устанавливает: используется только системный механизм'
  } }

  8 { Run-Cell 'f' 8 {
    $vf = Join-Path (Get-DataDir) 'vpn.json'
    if (-not (Test-Path $vf)) {
      $tpl = @'
{
  "name": "CELL65-VPN",
  "server": "vpn.example.com",
  "user": "login",
  "pass": "password",
  "type": "IKEv2",
  "psk": ""
}
'@
      Set-Content $vf $tpl -Encoding UTF8
      Add-Log 'ok' ('шаблон создан: ' + $vf + ' - заполни server/user/pass/type (IKEv2|SSTP|L2TP), потом клетки f2 и f3')
    } else { Add-Log 'i' ('vpn.json уже есть: ' + $vf) }
    Add-Log 'i' 'типы: IKEv2 (по умолчанию) | SSTP (443/tcp, проходит NAT) | L2TP (+ psk)'
  } }

  default { Add-Log '??' ('c06_vpn: нет клетки ' + $Cell) }
}
