# totp.ps1 - свой генератор 2FA-кодов на чистом PowerShell.
# НОЛЬ сторонних программ: только встроенный в Windows .NET (PowerShell 5.1+).
#
# Как пользоваться (путь адрыстотеля, доктрина repo-doctrine, глава 07):
#   1. GitHub -> Settings -> Password and authentication ->
#      Enable two-factor authentication -> Authenticator app ->
#      ссылка "enter this text code instead" -> скопировать ключ.
#   2. Сохранить ключ в файл totp.seed РЯДОМ с этим скриптом (одной строкой):
#        'ВСТАВЛЕННЫЙ_КЛЮЧ' | Set-Content -Encoding ASCII totp.seed
#   3. Получить код:
#        powershell -ExecutionPolicy Bypass -File totp.ps1
#   4. Вставить 6 цифр в GitHub. Код живёт 30 секунд.
#
# ВАЖНО: totp.seed НИКОГДА не коммитить в репозиторий и не пересылать в чат.
# Сид хранится только локально. Скрипт никуда не ходит по сети.
# Проверено на векторах RFC 6238 (SHA-1): 5/5 зелёные (TH-GH-04).
param(
    [string]$Seed = '',
    [string]$SeedFile = '',
    [long]$UnixTime = 0,   # для теста: зафиксировать время
    [int]$Period = 30,
    [int]$Digits = 6
)
$ErrorActionPreference = 'Stop'
if (-not $Seed -and -not $SeedFile) { $SeedFile = Join-Path $PSScriptRoot 'totp.seed' }
if ($SeedFile) {
    if (-not (Test-Path $SeedFile)) { throw "Нет файла сида: $SeedFile" }
    $Seed = Get-Content -Raw $SeedFile
}
$raw = $Seed.ToUpper() -replace '[^A-Z2-7]', ''
if (-not $raw) { throw 'Сид пуст: нужен Base32-ключ из GitHub (буквы A-Z и цифры 2-7)' }

# Base32 -> байты (RFC 4648)
$alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
$bits = ''
foreach ($ch in $raw.ToCharArray()) {
    $idx = $alphabet.IndexOf($ch)
    if ($idx -lt 0) { throw "Лишний символ в сиде: $ch" }
    $bits += [Convert]::ToString($idx, 2).PadLeft(5, '0')
}
$n = [math]::Floor($bits.Length / 8)
if ($n -lt 1) { throw 'Сид слишком короткий' }
$key = New-Object byte[] $n
for ($i = 0; $i -lt $n; $i++) {
    $key[$i] = [Convert]::ToByte($bits.Substring($i * 8, 8), 2)
}

# Счётчик времени: 8 байт big-endian (RFC 6238)
if ($UnixTime -le 0) { $UnixTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$counter = [math]::Floor($UnixTime / $Period)
$msg = New-Object byte[] 8
for ($j = 7; $j -ge 0; $j--) {
    $msg[$j] = [byte]($counter -band 0xFF)
    $counter = [math]::Floor($counter / 256)
}
$hmac = New-Object System.Security.Cryptography.HMACSHA1 (, $key)
$hash = $hmac.ComputeHash($msg)

# Динамическое усечение (RFC 4226) + модуль 10^Digits
$off = $hash[$hash.Length - 1] -band 0xF
$value = ($hash[$off] -band 0x7F) * 16777216 + $hash[$off + 1] * 65536 + $hash[$off + 2] * 256 + $hash[$off + 3]
$code = ([long]($value % [math]::Pow(10, $Digits))).ToString().PadLeft($Digits, [char]'0')
$left = $Period - ($UnixTime % $Period)
Write-Output ("{0} (живёт ещё {1} с)" -f $code, $left)
