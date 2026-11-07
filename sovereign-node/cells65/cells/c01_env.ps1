# CELL-65 :: c01_env.ps1 - ряд A: СРЕДА (клетки a1..a8)
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'a' 1 {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = ('{0}.{1}' -f $cv.CurrentBuildNumber, $cv.UBR)
    Add-Log 'i' ('ОС: ' + $cv.ProductName + ' | DisplayVersion: ' + $cv.DisplayVersion + ' | build: ' + $build)
    Add-Log 'i' ('арх: ' + $env:PROCESSOR_ARCHITECTURE + ' | комп: ' + $env:COMPUTERNAME + ' | пользователь: ' + $env:USERNAME)
    try {
      $cs = Get-CimInstance Win32_ComputerSystem
      $ramGB = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
      Add-Log 'i' ('RAM: ' + $ramGB + ' ГБ')
    } catch {}
    try {
      $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
      Add-Log 'i' ('CPU: ' + $cpu.Name.Trim())
    } catch {}
    Add-Log 'i' 'поле: c01..c08 x 8 клеток = 64 | диспетчер = 65-я клетка'
  } }

  2 { Run-Cell 'a' 2 {
    Add-Log 'i' ('PowerShell: ' + $PSVersionTable.PSVersion.ToString())
    $c = Get-Curl
    if ($c) {
      $v = (& $c --version | Select-Object -First 1)
      Add-Log 'i' ('curl.exe: ' + $c + ' | ' + $v)
    } else {
      Add-Log '!!' 'curl.exe не найден (координата: Windows 10 1803+ содержит curl в System32)'
    }
    Add-Log 'i' ('.NET: ' + [Environment]::Version.ToString())
  } }

  3 { Run-Cell 'a' 3 {
    $isAdmin = $false
    try {
      $id = [Security.Principal.WindowsIdentity]::GetCurrent()
      $pr = New-Object Security.Principal.WindowsPrincipal($id)
      $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    if ($isAdmin) { Add-Log 'i' 'права: администратор' }
    else { Add-Log 'i' 'права: обычный пользователь (достаточно для всех клеток; админ нужен только для факта g6 winhttp и VPN-профиля -AllUserConnection)' }
  } }

  4 { Run-Cell 'a' 4 {
    Ensure-Dirs
    Add-Log 'i' ('корень поля: ' + (Get-Root))
    $t = Join-Path (Get-DataDir) 'writetest.txt'
    try {
      Add-Content -Path $t -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding UTF8
      Add-Log 'ok' 'запись в data\: работает'
    } catch { Add-Log '!!' ('запись в data\: ' + $_.Exception.Message) }
    try {
      $drv = $env:SystemDrive.Trim(':')
      $dd = Get-PSDrive -Name $drv
      Add-Log 'i' ('свободно на ' + $env:SystemDrive + ': ' + [Math]::Round($dd.Free / 1GB, 1) + ' ГБ')
    } catch {}
  } }

  5 { Run-Cell 'a' 5 {
    try { Add-Log 'i' ('культура: ' + (Get-Culture).Name + ' | интерфейс: ' + (Get-UICulture).Name) } catch {}
    try { Add-Log 'i' ('часовой пояс: ' + (Get-TimeZone).Id) } catch {}
    try { Add-Log 'i' ('кодировка консоли: ' + [Console]::OutputEncoding.WebName) } catch {}
  } }

  6 { Run-Cell 'a' 6 {
    try {
      $epUser = Get-ExecutionPolicy -Scope CurrentUser
      $epMach = Get-ExecutionPolicy -Scope LocalMachine
      Add-Log 'i' ('ExecutionPolicy: CurrentUser=' + $epUser + ' LocalMachine=' + $epMach + ' (CELL-65 запускается с -ExecutionPolicy Bypass, политику не меняет)')
    } catch {}
    try {
      $mp = Get-MpComputerStatus -ErrorAction Stop
      Add-Log 'i' ('Defender: ' + $mp.AMRunningMode + ' | реальное время защита: ' + $mp.RealTimeProtectionEnabled)
    } catch { Add-Log 'i' 'Defender: статус недоступен (модуль/права)' }
    Add-Log 'i' 'доктрина: ноль удалений, ноль вердиктов; изменения - только клетки g с бэкапом'
  } }

  7 { Run-Cell 'a' 7 {
    Show-Board
    Show-KeyFacts
  } }

  8 { Run-Cell 'a' 8 {
    Ensure-Dirs
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $lines = @()
    $lines += ('OS=' + $cv.ProductName + ' ' + $cv.DisplayVersion + ' build ' + $cv.CurrentBuildNumber + '.' + $cv.UBR)
    $lines += ('ARCH=' + $env:PROCESSOR_ARCHITECTURE)
    try { $lines += ('RAM_GB=' + [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)) } catch {}
    $lines += ('PS=' + $PSVersionTable.PSVersion.ToString())
    $isAdmin = $false
    try {
      $id = [Security.Principal.WindowsIdentity]::GetCurrent()
      $isAdmin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    $lines += ('ADMIN=' + $isAdmin)
    $lines += ('ROOT=' + (Get-Root))
    $p = Join-Path (Get-DataDir) 'env.txt'
    $lines | Set-Content $p -Encoding UTF8
    Add-Log 'ok' ('факты среды -> ' + $p)
  } }

  default { Add-Log '??' ('c01_env: нет клетки ' + $Cell) }
}
