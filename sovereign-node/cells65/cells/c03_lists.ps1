# CELL-65 :: c03_lists.ps1 - ряд C: СПИСКИ серверов (клетки c1..c8)
# v9: живой реестр источников (проверен API GitHub 2026-09-30). Мёртвые удалены
# (clarketm - 6 мес без обновлений; ShiftyTR/jetkai - мёртвы с 2023). Добавлены:
# monosans all.txt, roosterkid socks4, vakhov (http/socks4/socks5).
# Карантий мёртвых и зеркала jsdelivr - в lib65 (Save-RawList v9).
# СВОЙ список: data\sources.tsv, строки id|протокол|url - перекрывает встроенный реестр целиком.
param([int]$Cell = 0)
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib65.psm1') -Force -DisableNameChecking

function Run-All { for ($i = 1; $i -le 8; $i++) { $null = & $PSCommandPath -Cell $i } }

function Get-SourceRegistry {
  $custom = Join-Path (Get-DataDir) 'sources.tsv'
  if (Test-Path $custom) {
    $reg = @()
    foreach ($l in @(Get-Content $custom -Encoding UTF8)) {
      $q = $l -split '\|'
      if ($q.Count -ge 3 -and $q[0].Trim() -ne '' -and $q[2].Trim() -match '^https?://') {
        $reg += ,@($q[0].Trim(), $q[1].Trim(), $q[2].Trim())
      }
    }
    if ($reg.Count -gt 0) { Add-Log 'i' ('реестр: пользовательский sources.tsv (' + $reg.Count + ' потоков)'); return ,$reg }
    Add-Log '!!' 'sources.tsv есть, но валидных строк нет - берём встроенный реестр'
  }
  return ,@(
    @('thespeedx', 'http',   'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt'),
    @('thespeedx', 'socks4', 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks4.txt'),
    @('thespeedx', 'socks5', 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt'),
    @('monosans',  'http',   'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt'),
    @('monosans',  'socks4', 'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks4.txt'),
    @('monosans',  'socks5', 'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt'),
    @('monosans',  'all',    'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/all.txt'),
    @('mmpx12',    'http',   'https://raw.githubusercontent.com/mmpx12/proxy-list/master/http.txt'),
    @('mmpx12',    'socks4', 'https://raw.githubusercontent.com/mmpx12/proxy-list/master/socks4.txt'),
    @('mmpx12',    'socks5', 'https://raw.githubusercontent.com/mmpx12/proxy-list/master/socks5.txt'),
    @('zloi',      'http',   'https://raw.githubusercontent.com/zloi-user/hideip.me/main/http.txt'),
    @('zloi',      'socks4', 'https://raw.githubusercontent.com/zloi-user/hideip.me/main/socks4.txt'),
    @('zloi',      'socks5', 'https://raw.githubusercontent.com/zloi-user/hideip.me/main/socks5.txt'),
    @('vakhov',    'http',   'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/http.txt'),
    @('vakhov',    'socks4', 'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/socks4.txt'),
    @('vakhov',    'socks5', 'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/socks5.txt'),
    @('hookzof',   'socks5', 'https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt'),
    @('proxifly',  'all',    'https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/all/data.txt'),
    @('roosterkid','socks5', 'https://raw.githubusercontent.com/roosterkid/openproxylist/main/SOCKS5_RAW.txt'),
    @('roosterkid','socks4', 'https://raw.githubusercontent.com/roosterkid/openproxylist/main/SOCKS4_RAW.txt')
  )
}

# v9: группы источников разложены по клеткам c1..c7 по кругу (свой список ложится так же)
function Invoke-SourceGroups {
  param([int]$Cell)
  $reg = Get-SourceRegistry
  $groups = [ordered]@{}
  foreach ($r in $reg) {
    $id = $r[0]
    if (-not $groups.Contains($id)) { $groups[$id] = @() }
    $groups[$id] = @($groups[$id]) + ,@($r[1], $r[2])
  }
  $ids = @($groups.Keys)
  for ($gi = 0; $gi -lt $ids.Count; $gi++) {
    if (($gi % 7) -eq ($Cell - 1)) { Save-RawList $ids[$gi] $groups[$ids[$gi]] }
  }
}

switch ($Cell) {

  0 { Run-All }

  1 { Run-Cell 'c' 1 {
    Add-Log 'i' 'v9: clarketm исключён из реестра (6 мес без обновлений, факт API GitHub)'
    Invoke-SourceGroups -Cell 1
  } }

  2 { Run-Cell 'c' 2 { Invoke-SourceGroups -Cell 2 } }

  3 { Run-Cell 'c' 3 { Invoke-SourceGroups -Cell 3 } }

  4 { Run-Cell 'c' 4 { Invoke-SourceGroups -Cell 4 } }

  5 { Run-Cell 'c' 5 { Invoke-SourceGroups -Cell 5 } }

  6 { Run-Cell 'c' 6 { Invoke-SourceGroups -Cell 6 } }

  7 { Run-Cell 'c' 7 { Invoke-SourceGroups -Cell 7 } }

  8 { Run-Cell 'c' 8 {
    $raw = Join-Path (Get-DataDir) 'raw'
    $seen = @{}
    $out = New-Object System.Collections.Generic.List[string]
    $cnt = @{ 'http' = 0; 'socks4' = 0; 'socks5' = 0 }
    $bad = 0
    $cfCut = 0
    Get-ChildItem $raw -Filter '*.txt' -ErrorAction SilentlyContinue | ForEach-Object {
      $name = $_.BaseName
      $fileProto = ($name -split '_')[-1]
      foreach ($ln in (Get-Content $_.FullName -ErrorAction SilentlyContinue)) {
        $line = $ln.Trim()
        if ($line -eq '') { continue }
        $ip = ''; $port = ''; $proto = ''
        if ($line -match '^(https?|socks[45])://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):([0-9]{2,5})') {
          $proto = $Matches[1]; $ip = $Matches[2]; $port = $Matches[3]
        } elseif ($line -match '^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):([0-9]{2,5})') {
          $ip = $Matches[1]; $port = $Matches[2]
        } else { $bad++; continue }
        if ($proto -eq '') {
          if ($fileProto -eq 'http' -or $fileProto -eq 'socks4' -or $fileProto -eq 'socks5') { $proto = $fileProto }
          else { $bad++; continue }
        }
        if ($proto -eq 'https') { $proto = 'http' }
        # v11: чистка Cloudflare-мусора - IP сетей Cloudflare прокси быть не может
        # (CDN-грани, страницы ошибок 502/1015); сети - cloudflare.com/ips-v4
        if (Test-CfIp $ip) { $bad++; $cfCut++; continue }
        $key = $proto + '|' + $ip + '|' + $port
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = 1
        $src = ''
        if ($name -match '^([a-zA-Z0-9]+)_') { $src = $Matches[1] }
        $out.Add(($key + '|' + $src))
        $cnt[$proto]++
      }
    }
    $pool = Join-Path (Get-DataDir) 'pool.tsv'
    $out | Set-Content $pool -Encoding UTF8
    Add-Log 'ok' ('пул: ' + $cnt.http + ' http, ' + $cnt.socks4 + ' socks4, ' + $cnt.socks5 + ' socks5 (пропущено строк: ' + $bad + ', из них Cloudflare-IP: ' + $cfCut + ') -> ' + $pool)
  } }

  default { Add-Log '??' ('c03_lists: нет клетки ' + $Cell) }
}
