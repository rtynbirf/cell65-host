# CELL-65 :: c08_life.ps1 - ряд H: ЖИЗНЬ (h1..h8)
# Полимат-режим: установка один раз -> задача CELL65 при входе -> auto сам содержит поле.
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

function Show-Help2 {
  Write-Host ''
  Write-Host ' CELL-65 :: шпаргалка'
  Write-Host ' 65.cmd              - меню'
  Write-Host ' 65.cmd auto         - авто-цикл'
  Write-Host ' 65.cmd board        - статус'
  Write-Host ' 65.cmd c / d / e    - целый ряд (списки / проба / локальный прокси)'
  Write-Host ' 65.cmd cell a5      - одна клетка'
  Write-Host ' клетки g2/g3        - системный прокси ВКЛ / откат'
  Write-Host ' клетки f8/f2/f3     - свой VPN-сервер: шаблон -> профиль -> подключение'
  Write-Host ' журнал: logs\cell65.log'
  Write-Host ''
}

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'h' 1 {
    Ensure-Dirs
    $ps = Join-Path (Get-Root) '65.ps1'
    $exec = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $act = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps + '" auto'
    $ok = $false
    try {
      $a = New-ScheduledTaskAction -Execute $exec -Argument $act
      $t = New-ScheduledTaskTrigger -AtLogOn -User ("$env:USERDOMAIN\$env:USERNAME")
      $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
      Register-ScheduledTask -TaskName 'CELL65' -Action $a -Trigger $t -Settings $s -Force -ErrorAction Stop | Out-Null
      $ok = $true
      Add-Log 'ok' 'задача CELL65 (вход в систему -> auto, скрыто) зарегистрирована'
    } catch { Add-Log '!!' ('Register-ScheduledTask: ' + $_.Exception.Message) }
    if (-not $ok) {
      try {
        $tr = '"' + $exec + '" ' + $act
        & schtasks.exe /Create /F /TN 'CELL65' /TR $tr /SC ONLOGON | Out-Null
        $ok = $true
        Add-Log 'ok' 'задача CELL65 создана через schtasks (фоллбек)'
      } catch { Add-Log '!!' ('schtasks: ' + $_.Exception.Message) }
    }
    Set-Content (Join-Path (Get-DataDir) 'installed.flag') (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding UTF8
    try {
      $ws = New-Object -ComObject WScript.Shell
      $desk = [Environment]::GetFolderPath('Desktop')
      $lnk = $ws.CreateShortcut((Join-Path $desk 'CELL-65 (статус).lnk'))
      $lnk.TargetPath = (Join-Path (Get-Root) '65.cmd')
      $lnk.Arguments = 'board'
      $lnk.WorkingDirectory = (Get-Root)
      $lnk.Save()
      Add-Log 'ok' 'ярлык статуса на рабочем столе'
    } catch { Add-Log 'i' ('ярлык: ' + $_.Exception.Message) }
    Add-Log 'i' 'с этого момента: вход в систему -> auto (среда -> списки при старении -> проба -> gost -> здоровье). Системный прокси g2 включится сам, только если был включён до этого'
  } }

  2 { Run-Cell 'h' 2 {
    try { Unregister-ScheduledTask -TaskName 'CELL65' -Confirm:$false -ErrorAction Stop; Add-Log 'ok' 'задача CELL65 снята' } catch { Add-Log 'i' ('задача: ' + $_.Exception.Message) }
    try { Stop-Process -Name gost -Force -ErrorAction SilentlyContinue; Add-Log 'ok' 'gost остановлен' } catch {}
    $ap = Join-Path (Join-Path (Get-Root) 'cells') 'c07_apply.ps1'
    & $ap -Cell 3
    Remove-Item (Join-Path (Get-DataDir) 'installed.flag') -ErrorAction SilentlyContinue
    Add-Log 'ok' 'undo выполнен (данные и журнал сохранены в data\ и logs\ - ноль удалений)'
  } }

  3 { Run-Cell 'h' 3 {
    & (Join-Path (Get-Root) '65.ps1') auto
  } }

  4 { Run-Cell 'h' 4 {
    $loc = Join-Path (Join-Path (Get-Root) 'cells') 'c05_local.ps1'
    & $loc -Cell 4
    if ((Get-Flag 'gost_ok') -ne '1') {
      Add-Log '--' 'watch: здоровье потеряно -> смена upstream (e7)'
      & $loc -Cell 7
      & $loc -Cell 4
      if ((Get-Flag 'gost_ok') -ne '1') {
        Add-Log '--' 'watch: полная перепроба (ряды c и d)'
        & (Join-Path (Join-Path (Get-Root) 'cells') 'c03_lists.ps1') -Cell 0
        & (Join-Path (Join-Path (Get-Root) 'cells') 'c04_probe.ps1') -Cell 0
        & $loc -Cell 2
        & $loc -Cell 3
        & $loc -Cell 4
      }
    } else { Add-Log 'ok' 'watch: здоровье в норме' }
    if (Test-Path (Join-Path (Get-DataDir) 'installed.flag')) {
      & (Join-Path (Join-Path (Get-Root) 'cells') 'c07_apply.ps1') -Cell 2
    }
  } }

  5 { Run-Cell 'h' 5 {
    $lp = Join-Path (Get-LogDir) 'cell65.log'
    if (Test-Path $lp) {
      Add-Log 'i' '--- журнал (последние 40 строк) ---'
      Get-Content $lp -Tail 40 | ForEach-Object { Write-Host ('  ' + $_) }
    } else { Add-Log 'i' 'журнала ещё нет' }
  } }

  6 { Run-Cell 'h' 6 {
    Ensure-Dirs
    $d = Get-DataDir
    $p = Join-Path $d 'report65.txt'
    $lines = @()
    $lines += '=============================================='
    $lines += ('CELL-65 :: полный отчёт ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    $lines += ('корень: ' + (Get-Root))
    $lines += '=============================================='
    $lines += '-- доска --'
    $lines += @(Get-BoardText)
    $lines += '-- среда (a8) --'
    if (Test-Path (Join-Path $d 'env.txt')) { $lines += @(Get-Content (Join-Path $d 'env.txt')) } else { $lines += 'нет' }
    $lines += '-- выбор (d6) --'
    if (Test-Path (Join-Path $d 'best.json')) { $lines += @(Get-Content (Join-Path $d 'best.json')) } else { $lines += 'нет' }
    $lines += '-- прокси ОС --'
    $v = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($v) { $lines += ('ProxyEnable=' + $v.ProxyEnable + ' ProxyServer=' + $v.ProxyServer) }
    $lines += '-- журнал (хвост 60) --'
    $lp = Join-Path (Get-LogDir) 'cell65.log'
    if (Test-Path $lp) { $lines += @(Get-Content $lp -Tail 60) }
    $lines | Set-Content $p -Encoding UTF8
    Add-Log 'ok' ('отчёт -> ' + $p)
  } }

  7 { Run-Cell 'h' 7 {
    Show-Status
  } }

  8 { Run-Cell 'h' 8 {
    Show-Help2
  } }

  default { Add-Log '??' ('c08_life: нет клетки ' + $Cell) }
}
