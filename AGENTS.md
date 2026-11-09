# AGENTS.md — императивные инструкции для агентов

## Что это за репо
«Антицензор» MV3 — Chrome-расширение обхода блокировок (PAC/DNR/WebRTC/auth-прокси,
без телеметрии) + sovereign-node (сервер sing-box, PAC-сервер, Windows-скрипты).
Аккаунт общий — другие агенты публикуют параллельно, история только растёт.

## Карта репо
- `anticensormv3/` — расширение MV3: manifest.json, background.js, lib/ (pac-engine,
  dnr-manager, defaults), popup/options/newtab, rules/ (ads.json, trackers.json)
- `sovereign-node/` — серверная линия: sing-box конфиги, install-скрипты, ddns,
  windows/ (autopilot, provision), chrome-ext (старшая версия)
- `pac/` — standalone PAC: build_pac.py → antizensor.pac
- `tools/` — test_pac.mjs (функциональные тесты), hosts_to_dnr.py
- `packs/` — hosts-стартер, exceptions, antizensor-list
- `MAILBOX.md` — межагентный почтовый ящик (append-only, письмо = коммит;
  перед работой прочитай ленту, ответ оформляй по протоколу внутри)
- `docs/SOURCES.md` — журнал верификации фактов

## Команды
- тесты (из корня): `node tools/test_pac.mjs` — зелёный = «ВСЕ PAC-ТЕСТЫ ЗЕЛЁНЫЕ»
- сборка standalone PAC: `python3 pac/build_pac.py`
- конвертер hosts: `python3 tools/hosts_to_dnr.py`

## Жёсткие правила (DO NOT)
- НЕ делай force-push и НЕ удаляй ветку main
- НЕ пушь без `git fetch` и ff-only-сверки — чужие агенты публикуют параллельно
- НЕ добавляй внешнюю телеметрию/аналитику — архитектурный запрет
- НЕ добавляй `dnsResolve`/`isInNet` в PAC и не включай `mandatory` — сознательное
  решение, зафиксировано в docs/SOURCES.md
- НЕ поднимай `minimum_chrome_version` ниже 121 без веской причины
- НЕ вноси факт/URL без записи в docs/SOURCES.md
- НЕ правь и не удаляй чужие письма в MAILBOX.md — append-only, правка только
  поля «Статус» чужого письма
- Токены не печатаются в выводе и не попадают в код/коммиты

## Definition of Done
1. `node tools/test_pac.mjs` — все тесты зелёные
2. manifest.json и rules/*.json — валидный JSON
3. Новые факты верифицированы и записаны в SOURCES.md
4. ff-merge удалёнки перед пушем; коммит-месседж по-русски: что и почему

## Гигиена агента (Волна ×10, 2026-11-10)

Канон: repo-doctrine → `21-гигиена-уведомлений-и-красного-CI-2026-11-09.md`. Вход по закону: `github-runbook#10` (РЕЕСТР НЕДОДЕЛАННОГО · закон §5) + РЕЕСТР-КОСЯКОВ-ИИ + АНАТОМИЯ-КОСЯКОВ-ИИ (polimat-hub) — читать ДО первого действия.

1. Красный CI от твоего коммита — твой долг: живой зелёный прогон до конца сессии (rerun/диспатч/лат). Честный красный (внешний блок) — пломбой в github-runbook#10, не прятать.
2. Новые файлы — в манифесты тем же коммитом: SPDX/REUSE.toml, MANIFEST/portability.json, геном cell-swarm/swarm.json (пин следит за телом).
3. Не плодить уведомления: свой прогон доведи до зелёного; входящие треды разобрать и пометить прочитанными; UNREAD=0 — норма.
4. Пуш-гигиена: `pull --rebase` перед пушем; force-push запрещён; чужие волны и авто-коммиты (§3 реестра) не трогать; дубль снят честно = нет дубля.
