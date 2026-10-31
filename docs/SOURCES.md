# Журнал верификации фактов (антигаллюцинационный протокол)

Все технические утверждения README и кода проверены по первоисточникам.
Дата проверки: **2026-10-31** (если не указано иное).

| # | Факт (как использован в проекте) | Источник | Статус |
|---|---|---|---|
| 1 | `chrome.proxy`: режимы `direct`/`auto_detect`/`pac_script`/`fixed_servers`/`system`; `PacScript{data,url,mandatory}`; `ProxyServer{host,port,scheme}`; схемы `http\|https\|quic\|socks4\|socks5`; порты по умолчанию: socks5→1080; требуется permission `proxy`; `settings.set({value,scope:'regular'})`; `bypassList` форматы (`<local>`, CIDR, IP-литерал); событие `onProxyError{error,fatal,details}` | Официальные доки Chrome — developer.chrome.com/docs/extensions/reference/api/proxy (страница помечена «Last updated 2026-10-29 UTC») | ✅ сфетчено 2026-10-31 |
| 2 | DNR: динамических правил **30 000** (с Chrome 121; ранее 5 000); сессионных 5 000; статических наборов до 100, одновременно включено до 50; `GUARANTEED_MINIMUM_STATIC_RULES = 30 000`; permission `declarativeNetRequest` даёт `block`/`allow`/`allowAllRequests` **без** host-доступа; для действий с host-доступом нужно `declarativeNetRequestWithHostAccess`; `setExtensionActionOptions({displayActionCountAsBadgeText})` | Официальные доки — developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest | ✅ сфетчено 2026-10-31 |
| 3 | `webRequest.onAuthRequired` в MV3: опция **`asyncBlocking`** (и `blocking`); для HTTP-авторизации нужно разрешение **`webRequestAuthProvider`**; `webRequestBlocking` в MV3 недоступен (кроме policy-расширений) | Официальные доки — developer.chrome.com/docs/extensions/reference/api/webRequest | ✅ сфетчено 2026-10-31 |
| 4 | Chrome при SOCKS-прокси **резолвит DNS напрямую** (нет socks5h-семантики) → рекомендация включать Безопасный DNS (DoH) или использовать HTTP(S)-прокси для туннелирования имён | Chromium docs — «Configuring a SOCKS proxy server in Chrome» (chromium.googlesource.com, раздел proxy.md); сниппет «DNS resolves directly» | ✅ найдено 2026-10-31 |
| 5 | Закат MV2: с июня 2024 — отключение на pre-stable каналах; в течение 2025 — стабильные браузеры; финальное удаление enterprise/экспериментальных обходов — **июнь 2026** | 9to5google (30.05.2024), hilars.dev (17.08.2024), mallory.ai (12.06.2026) | ✅ найдено 2026-10-31 |
| 6 | Стандартизированный неймспейс `browser.*` доступен с Chrome 148 (проект использует `chrome.*` — совместимо) | Официальные доки Chrome (баннер на страницах proxy/declarativeNetRequest) | ✅ сфетчено 2026-10-31 |
| 7 | Ключ манифеста `chrome_url_overrides.newtab` заменяет новую вкладку | Официальные доки манифеста Chrome; практика dev.to (25.07.2017) | ✅ найдено 2026-10-31 |
| 8 | Политика CWS: «single purpose, narrow and easy-to-understand»; замена новых вкладок требует, чтобы это была основная функция — для Store, не для unpacked-установок | The Verge (20.12.2013) о правилах Chrome Web Store; действующая Program Policy CWS | ✅ найдено 2026-10-31 |
| 9 | Типичные порты локальных прокси-стеков: Xray/v2rayN — 10808, sing-box — 2080, shadowsocks — 1080 | Заявлено как «типичные», README прямо требует сверять с конфигом пользователя | ⚠️ эвристика, не факт — помечено в README |
| 10 | Домены `rules/*.json` и `packs/hosts-starter.txt` — классические рекламные сети/трекеры, присутствующие в публичных блок-листах (StevenBlack/AdGuard и т.п.) | Общеизвестные факты; при спорных сайтах используйте исключения §4 | ⚠️ эвристика; состав минимален и консервативен |
| 11 | Стартовый список PAC (twitter/x/facebook/instagram) — «ограничены в ряде юрисдикций» | Общеизвестный факт; README помечает список как ПРИМЕР ФОРМАТА, не как юридически актуальный реестр | ⚠️ пример формата |

## Что НЕ заявляется

- Никаких утверждений о текущих реестрах блокировок конкретной страны/даты — список PAC пустой по смыслу и заполнен примерами формата.
- Никаких чисел о «количестве заблокированных пользователей» и прочей неисследованной статистики.
- Порты клиентских стеков — только как ориентиры с требованием сверять конфиг.

## Ограничения по тестам

- Функциональные тесты PAC-движка: 23/23 зелёные (node, vm-песочница с полифиллом `shExpMatch`).
- В живом Chrome расширение не запускалось (в песочнице нет браузера с профилем); API-вызовы взяты строго в сигнатурах официальных доков из пп. 1–3.
