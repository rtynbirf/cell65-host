# RESTORE.md — самовоскрешение репозитория

## Что это за репо
«Антицензор» MV3: Chrome-расширение обхода блокировок (PAC/DNR/WebRTC) +
sovereign-node. Приватный репо: github.com/rtynbirf/cell65-host (main).

## Восстановление из bundle (полный клон: ветки + теги)
```bash
git clone cell65-host.bundle cell65-host
cd cell65-host
git remote add origin https://github.com/rtynbirf/cell65-host.git
git push -u origin main && git push --tags
```

## Где взять свежий bundle
1. Артефакт Actions этого репо: workflow `bundle-backup`
   (понедельник 03:00 UTC, хранение 90 дней)
2. Локальные бандлы владельца: `cell65-host-fresh-*.bundle`

## Если репо на GitHub потеряно
Пересоздать приватным: github-runbook → 01-sozdanie-repo.md (API-путь, ответ 201).

## Ключевые точки
- Теги: v1.0.0, v1.0.0-mv3, v1.1.0
- Проверка после восстановления: `node tools/test_pac.mjs` → все зелёные
