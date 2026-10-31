// «Антицензор MV3» — значения по умолчанию.
// Все дефолты согласованы с официальной документацией Chrome:
//   * scheme socks5 → порт по умолчанию 1080 (docs: developer.chrome.com/docs/extensions/reference/api/proxy)
//   * режимы: direct | pac_script | fixed_servers (то же место)
//   * лимит динамических правил DNR: 30 000 начиная с Chrome 121
//     (docs: developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest)
export const DEFAULTS = Object.freeze({
  // Режим прокси:
  //   pac    — PAC-скрипт: через прокси идут только домены из списка «Антицензор» (или всё, если pacScope=all)
  //   global — весь трафик через прокси (fixed_servers)
  //   direct — без прокси
  mode: 'pac',
  pacScope: 'list',          // 'list' — по списку; 'all' — всё, кроме исключений
  pacSource: 'local',        // 'local' — PAC из своего списка; 'url' — внешний PAC-файл (напр., «АнтиЗапрет»)
  pacUrl: '',                // URL внешнего PAC (используется при pacSource='url')
  proxyScheme: 'socks5',     // http | https | socks5
  proxyHost: '127.0.0.1',
  proxyPort: 1080,
  proxyAuthEnabled: false,
  proxyUser: '',
  proxyPass: '',
  // Служебный обход прокси (bypassList; форматы из официальных доков proxy API)
  bypass: ['localhost', '127.0.0.1', '[::1]', '<local>'],
  // Список «Антицензор»: домены, которые в режиме pac/list идут через прокси
  antizensor: ['twitter.com', 'x.com', 'facebook.com', 'instagram.com'],
  // Исключения: домены, которые всегда идут напрямую (DIRECT)
  exceptions: [],
  // hosts-блокировка через declarativeNetRequest (статические наборы rules/*.json)
  blockAds: true,
  blockTrackers: true,
  // Приватность: скрывать локальные IP в WebRTC (chrome.privacy.webrtc)
  webrtcHideIp: true,
  // Показывать счётчик заблокированных запросов на иконке (DNR displayActionCountAsBadgeText)
  badgeCount: true
});

// Публичные PAC-сервисы для кнопки «Работает сразу».
// URL взяты с официальных страниц сервиса «АнтиЗапрет» (антзапрет.prostovpn.org,
// зеркало antizapret-1); проверены 2026-10-31: прямой запрос PAC из песочницы
// вне RU возвращает 403 "Your geoip is not RU... THE SERVICE WORKS ONLY IN RUSSIA!"
// — т.е. сервис работает только с RU-гео (см. docs/SOURCES.md).
export const QUICK_PACS = Object.freeze({
  antizapret: {
    label: 'публичный «АнтиЗапрет»',
    urls: [
      'https://antizapret.prostovpn.org/proxy.pac',
      'https://p.thenewone.lol:8443/proxy.pac'
    ]
  }
});

export function clone(obj) {
  return JSON.parse(JSON.stringify(obj));
}
