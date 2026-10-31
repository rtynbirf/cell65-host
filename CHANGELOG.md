# CHANGELOG — cell65-host

Формат — [Keep a Changelog 1.1.0](https://keepachangelog.com/ru/1.1.0/), версионирование — [semver](https://semver.org/lang/ru/).
Репозиторий — коробка «настроил и забыл»: тег ставит точку, дальше в лог попадают только заметные изменения.

## [1.0.0] — 2026-10-30

Первый релиз: полный комплект СУВЕРЕННОГО УЗЛА + закрытие находок аудита `AUDIT_CELL65_LLM.md` (Level 4).

### Added
- СУВЕРЕННЫЙ УЗЕЛ: лестница из трёх независимых транспортов — T1 VLESS+Reality,
  T2 VLESS+WS за Cloudflare CDN, T3 Hysteria2 — с urltest-авторотацией и развязкой
  RU/не-RU (geosite/geoip-ru, TUN, hijack-dns)
- `sovereign-node/server/install-server.sh` — установка сервера на VPS (Ubuntu), идемпотентная
- `sovereign-node/windows/install-sovereign-node.ps1` — установка клиента на Windows 11,
  рендер конфига из `node.env`, `-RenderOnly` для пробы без подключения
- `sovereign-node/windows/provision-edge.ps1` — домен в Cloudflare: зона, SSL Full,
  DNS-записи @/direct (идемпотентно, с ожиданием активации NS)
- `sovereign-node/windows/deprovision-edge.ps1` — обратимый съём Cloudflare-края:
  dry-run по умолчанию, `-Apply` удаляет DNS-записи sovereign-node, `-Apply -DeleteZone`
  сносит зону целиком (аудит C8: у каждой операции есть откат)
- `sovereign-node/server/ddns-update.sh` — DDNS для VPS с динамическим IP
- CI `.github/workflows/selftest.yml`: сервер E2E на Ubuntu 24.04 (полная установка,
  службы/порты, `sing-box check`, env-режим однострочника) + клиент-рендер на Windows
  (RenderOnly без T2 и с T2)
- Документация: `README-RUNBOOK.md` («настроил и забыл», карта пакета, диагностика),
  раздел «Честные границы» — сертификаты (C1), NAT/Hysteria2 (C2), DNS-утечка (C4)

### Changed
- urltest `tolerance` 50 → 150 мс (рендерер + пример конфига): на нестабильных
  линках ±100 мс за 3-минутное окно «толерантность 50» давала флаппинг лестницы;
  150 мс переключает транспорт только при реальной разнице (аудит C3)

### Security
- `sing-box` пинуется конкретной версией в обоих установщиках; обновление =
  поднять версию в скриптах, CI прогоняет E2E (аудит C5, closes #1)
- CI: у фиктивного `VPS_IP=203.0.113.10` стоит предупреждение — TEST-NET-3
  (RFC 5737), рендер только с `-RenderOnly`, иначе вечный hang (аудит C6)

[1.0.0]: https://github.com/rtynbirf/cell65-host/releases/tag/v1.0.0
