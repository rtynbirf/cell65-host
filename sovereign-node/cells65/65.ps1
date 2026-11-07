# ============================================================
# CELL-65 :: 65.ps1 - диспетчер, 65-я клетка
# 8 файлов x 8 клеток = 64 клетки (целое поле) + диспетчер = 65.
# Режимы: auto | menu | board | help | cell a5 | ряды a..h
# v9: универсальный критерий (дом авто, анти-соседи, org cap), меритократия (score),
#     карантин мёртвых источников + зеркала jsdelivr
# ============================================================
param(
  [string]$Cmd = '',
  [string]$Arg = '',
  [switch]$Quiet
)
$ErrorActionPreference = 'Continue'
try { $host.UI.RawUI.WindowTitle = 'CELL-65' } catch {}
Import-Module (Join-Path $PSScriptRoot 'lib65.psm1') -Force -DisableNameChecking

$script:Rows = @{
  'a' = 'c01_env.ps1';   'b' = 'c02_net.ps1'
  'c' = 'c03_lists.ps1'; 'd' = 'c04_probe.ps1'
  'e' = 'c05_local.ps1'; 'f' = 'c06_vpn.ps1'
  'g' = 'c07_apply.ps1'; 'h' = 'c08_life.ps1'
}
$script:RowNames = @{
  'a' = 'СРЕДА'; 'b' = 'СЕТЬ'; 'c' = 'СПИСКИ'; 'd' = 'ПРОБА'
  'e' = 'ЛОКАЛЬ'; 'f' = 'VPN'; 'g' = 'ПРОКСИ ОС'; 'h' = 'ЖИЗНЬ'
}

function Invoke-Row {
  param([string]$Row)
  $f = Join-Path (Join-Path (Get-Root) 'cells') $script:Rows[$Row]
  if (-not (Test-Path $f)) { Add-Log '!!' ('нет файла клетки: ' + $f); return }
  Add-Log '--' ('ряд ' + $Row + ' (' + $script:RowNames[$Row] + ')')
  $null = & $f -Cell 0
}

function Invoke-CellId {
  param([string]$Id)
  $Id = $Id.ToLower()
  if ($Id -notmatch '^[a-h][1-8]$') { Add-Log '!!' ('координата клетки: a1..h8 (получено: ' + $Id + ')'); return }
  $row = $Id.Substring(0, 1); $col = [int]$Id.Substring(1, 1)
  $f = Join-Path (Join-Path (Get-Root) 'cells') $script:Rows[$row]
  Add-Log '--' ('клетка ' + $Id + ' (' + $script:RowNames[$row] + ')')
  $null = & $f -Cell $col
}

function Show-Help {
  Write-Host ''
  Write-Host ' CELL-65 :: 64 клетки (8x8) + диспетчер (65-я клетка)'
  Write-Host ' ---------------------------------------------------'
  Write-Host ' 65.cmd                 меню (интерактив)'
  Write-Host ' 65.cmd auto            авто-цикл: среда -> списки -> проба -> локальный прокси -> здоровье'
  Write-Host ' 65.cmd board           доска статуса + ключевые факты'
  Write-Host ' 65.cmd c               весь ряд c (СПИСКИ)      | 65.cmd d  весь ряд d (ПРОБА)'
  Write-Host ' 65.cmd cell a5         одна клетка по координате a1..h8'
  Write-Host ' 65.cmd help            эта справка'
  Write-Host ''
  Write-Host ' ряды: a среда | b сеть | c списки | d проба | e локальный прокси | f vpn | g прокси ОС | h жизнь'
  Write-Host ' выбор d6 = радиус СПБ (59.9386,30.3141): вне домена РФ, кольцо дистанции, затем скорость.'
  Write-Host ' Chrome: папка chrome-mv3 - ручное переключение серверов (Manifest V3; установка - README).'
  Write-Host ' VPN - родной клиент Windows (RasMan): профиль создаётся только по твоим данным (f2/f8).'
  Write-Host ' Ничего не удаляет; изменения системы - только клетки g (с бэкапом и откатом g3).'
  Write-Host ''
}

function Show-Status {
  Show-Board
  Show-KeyFacts
}

function Invoke-Auto {
  # v8 (аудит): одна копия AUTO - задача на вход в систему и ручной [8] не гоняются
  # параллельно. Брошенный мьютекс (прошлый запуск упал) = продолжаем.
  $C65Mutex = New-Object System.Threading.Mutex($false, 'CELL65-Auto')
  $owned = $false
  try { $owned = $C65Mutex.WaitOne(0) } catch { $owned = $true }
  if (-not $owned) { Add-Log 'i' 'AUTO уже выполняется - второй запуск пропущен'; return }
  Add-Log '==' 'CELL-65 AUTO старт'
  Ensure-Dirs
  $cells = Join-Path (Get-Root) 'cells'

  $null = & (Join-Path $cells 'c01_env.ps1') -Cell 1
  $null = & (Join-Path $cells 'c01_env.ps1') -Cell 3

  $gost = Join-Path (Get-BinDir) 'gost.exe'
  if (-not (Test-Path $gost)) {
    Add-Log '--' 'gost отсутствует -> клетка e1'
    $null = & (Join-Path $cells 'c05_local.ps1') -Cell 1
  }

  $best = Join-Path (Get-DataDir) 'best.json'
  $fresh = $false
  if (Test-Path $best) {
    $ageH = ((Get-Date) - (Get-Item $best).LastWriteTime).TotalHours
    if ($ageH -lt 24) { $fresh = $true }
  }
  if (-not $fresh) {
    Add-Log '--' 'best.json отсутствует или старше 24ч -> ряды c и d'
    Invoke-Row 'c'
    Invoke-Row 'd'
  }

  # v7: порядок e2 -> e3 -> e4. Раньше e2 не вызывался: на холодном старте e3 не находил
  # gost_args.txt, gost не стартовал, здоровье падало впустую, и e7 перескакивал на
  # следующего кандидата, не попробовав лучшего из d6.
  $null = & (Join-Path $cells 'c05_local.ps1') -Cell 2
  $null = & (Join-Path $cells 'c05_local.ps1') -Cell 3
  $null = & (Join-Path $cells 'c05_local.ps1') -Cell 4
  $st = Get-Flag 'gost_ok'
  if ($st -ne '1') {
    Add-Log '--' 'здоровье: сбой -> смена upstream (e7)'
    $null = & (Join-Path $cells 'c05_local.ps1') -Cell 7
  }

  if (Test-Path (Join-Path (Get-DataDir) 'installed.flag')) {
    $null = & (Join-Path $cells 'c07_apply.ps1') -Cell 2
  } else {
    Add-Log 'i' 'системный прокси не тронут (нет installed.flag; координата: 65.cmd h1 или меню [7])'
  }
  Add-Log '==' 'CELL-65 AUTO финиш'
  try { $C65Mutex.ReleaseMutex() } catch {}
  try { $C65Mutex.Dispose() } catch {}
}

function Show-Menu {
  while ($true) {
    Clear-Host
    Write-Host '====================================================='
    Write-Host ' CELL-65  ::  64 клетки (8x8) + диспетчер'
    Write-Host '====================================================='
    Show-Status
    Write-Host ''
    Write-Host ' [1] СРЕДА + СЕТЬ      (a,b)   факты о машине и канале'
    Write-Host ' [2] СПИСКИ            (c)     GitHub: давние открытые источники'
    Write-Host ' [3] ПРОБА И ВЫБОР     (d)     радиус СПБ: вне РФ, кольцо, скорость'
    Write-Host ' [4] ЛОКАЛЬНЫЙ ПРОКСИ  (e)     gost 127.0.0.1:18080/18081'
    Write-Host ' [5] VPN               (f)     родной клиент Windows (RasMan)'
    Write-Host ' [6] ПРОКСИ ОС ВКЛ/ВЫКЛ(g)     с бэкапом и откатом'
    Write-Host ' [7] ЖИЗНЬ             (h)     установка/undo/журнал/отчёт'
    Write-Host ' [8] АВТО              полный цикл как по кнопке'
    Write-Host ' [9] ПОМОЩЬ'
    Write-Host ' [0] ВЫХОД'
    $k = Read-Host 'номер'
    switch ($k) {
      '1' { Invoke-Row 'a'; Invoke-Row 'b' }
      '2' { Invoke-Row 'c' }
      '3' { Invoke-Row 'd' }
      '4' { Invoke-Row 'e' }
      '5' { Invoke-Row 'f' }
      '6' { Invoke-Row 'g' }
      '7' { Invoke-Row 'h' }
      '8' { Invoke-Auto }
      '9' { Show-Help }
      '0' { return }
    }
    Write-Host ''
    try { Read-Host 'Enter - в меню' | Out-Null } catch { return }
  }
}

Ensure-Dirs
switch ($Cmd.ToLower()) {
  '' {
    if ($Quiet -or -not [Environment]::UserInteractive) { Invoke-Auto } else { Show-Menu }
  }
  'auto'  { Invoke-Auto }
  'menu'  { Show-Menu }
  'board' { Show-Status }
  'help'  { Show-Help }
  'cell'  { Invoke-CellId $Arg }
  default {
    $c = $Cmd.ToLower()
    if ($script:Rows.ContainsKey($c)) { Invoke-Row $c }
    elseif ($c -match '^[a-h][1-8]$') { Invoke-CellId $c }
    else { Show-Help }
  }
}
