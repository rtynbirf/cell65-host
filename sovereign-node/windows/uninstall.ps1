# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — полное снятие с Windows (если когда-нибудь понадобится)
#  powershell -ExecutionPolicy Bypass -File uninstall.ps1
#  Не трогает: твой DNS-щит (нативный DoH), файлы node.env в папке пакета.
# ============================================================
#Requires -RunAsAdministrator
$Svc = "SovereignNode"
$Base = "C:\Program Files\sovereign-node"
$Data = "C:\ProgramData\sovereign-node"

Stop-Service $Svc -Force -ErrorAction SilentlyContinue
sc.exe delete $Svc | Out-Null
Start-Sleep 2
Remove-Item $Data -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $Base -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Служба, конфиги и бинарь удалены. TUN-адаптер исчезнет сам вместе с процессом."
Write-Host "node.env в папке пакета сохранён — переустановка вернёт всё как было за один запуск."
