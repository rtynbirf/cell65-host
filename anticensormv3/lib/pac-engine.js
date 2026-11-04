// «Антицензор MV3» — генератор PAC-скрипта и конфигов chrome.proxy.
//
// Лучшие практики, заложенные в генерацию (все — из официальной документации
// Chromium/Chrome, см. docs/SOURCES.md в корне репозитория):
//   1. Никаких dnsResolve()/isInNet() внутри PAC — они синхронно блокируют
//      сетевой поток Chrome и ломаются при IPv6. Только строковые проверки
//      по имени хоста.
//   2. ES5-совместимый код PAC (charCodeAt вместо endsWith и т.п.) — PAC
//      исполняется в ограниченном окружении.
//   3. bypass локальных/приватных адресов: localhost, 127/8, 10/8,
//      172.16/12, 192.168/16, 169.254/16, ::1, fe80::/10, fc00::/7.
//   4. Цепочка возврата "SOCKS5 host:port; DIRECT" — при недоступности
//      прокси браузер не умирает (pacScript.mandatory = false).
//   5. Для fixed_servers используется singleProxy (покрывает HTTP+HTTPS+FTP
//      одним объектом) + fallbackProxy + bypassList.

const HOSTNAME_RE = /^[a-z0-9.*-]+$/;

/** Нормализация списка доменов: нижний регистр, без точек на концах,
 *  поддержка wildcards (*.example.com, *.example.com:80 не поддерживаем —
 *  порты в PAC-матчинге не нужны, порт входит в shExpMatch только для
 *  shExpMatch по host — не используется). Дедупликация. */
export function normalizeDomains(list) {
  const out = [];
  const seen = new Set();
  for (let item of list || []) {
    let d = String(item || '').trim().toLowerCase();
    if (!d) continue;
    // срезаем схему/путь, если вставили URL целиком
    d = d.replace(/^[a-z][a-z0-9+.-]*:\/\//, '');
    d = d.split('/')[0].split(':')[0];
    // adblock-стиль
    if (d.startsWith('||')) d = d.slice(2);
    if (d.endsWith('^')) d = d.slice(0, -1);
    while (d.startsWith('.')) d = d.slice(1);
    if (!d || d === '*' || !HOSTNAME_RE.test(d)) continue;
    if (!/[a-z0-9]/.test(d)) continue; // отбрасываем «***» и прочий мусор без букв/цифр
    if (seen.has(d)) continue;
    seen.add(d);
    out.push(d);
  }
  return out;
}

/** Служебные функции, встраиваемые в тело PAC (ES5-стиль). */
const PAC_HELPERS = `
  function ac65IsPrivateHost(h) {
    if (h === 'localhost' || (h.length > 10 && h.slice(h.length - 10) === '.localhost')) return true;
    var isIp = (h.charCodeAt(0) >= 48 && h.charCodeAt(0) <= 57);
    if (isIp) {
      var p = h.split('.');
      if (p.length !== 4) return false;
      if (p[0] === '10' || p[0] === '127' || p[0] === '0') return true;
      if (p[0] === '192' && p[1] === '168') return true;
      if (p[0] === '172' && p[1] >= 16 && p[1] <= 31) return true;
      if (p[0] === '169' && p[1] === '254') return true;
      return false;
    }
    if (h.indexOf(':') !== -1) { // IPv6-литерал
      if (h === '::1' || h === '[::1]') return true;
      if (h.indexOf('fe80') === 0) return true;      // link-local
      if (h.indexOf('fc') === 0 || h.indexOf('fd') === 0) return true; // fc00::/7 unique local
      return false;
    }
    return false;
  }
  function ac65Match(h, list) {
    for (var i = 0; i < list.length; i++) {
      var d = list[i];
      var wc = d.charCodeAt(0) === 42; // '*'
      if (wc) {
        if (shExpMatch(h, d)) return true;
      } else if (h === d) {
        return true;
      } else if (h.length > d.length + 1 &&
                 h.charCodeAt(h.length - d.length - 1) === 46 && // '.'
                 h.slice(h.length - d.length) === d) {
        return true; // поддомен: h === *.d
      }
    }
    return false;
  }
`;

/** Строит текст PAC-скрипта из конфига. */
export function buildPacData(cfg) {
  const proxied = normalizeDomains(cfg.antizensor);
  const exceptions = normalizeDomains(cfg.exceptions);
  const proxyStr = `${cfg.proxyScheme} ${cfg.proxyHost}:${cfg.proxyPort}`.toUpperCase();
  const chain = `${proxyStr}; DIRECT`;
  const scopeAll = cfg.pacScope === 'all';
  const generatedAt = new Date().toISOString();

  return `// «Антицензор» PAC — сгенерирован расширением Антицензор MV3
// ${generatedAt}
// Режим: ${scopeAll ? 'pac/all (всё через прокси, кроме исключений)' : 'pac/list (по списку)'}
// Прокси: ${proxyStr}; резерв — DIRECT (mandatory=false)
var AC65_CHAIN = '${chain}';
var AC65_SCOPE_ALL = ${scopeAll ? 'true' : 'false'};
var AC65_PROXIED = ${JSON.stringify(proxied)};
var AC65_EXCEPTIONS = ${JSON.stringify(exceptions)};
${PAC_HELPERS}
function FindProxyForURL(url, host) {
  host = (host || '').toLowerCase();
  if (!host) return 'DIRECT';
  if (ac65IsPrivateHost(host)) return 'DIRECT';
  if (ac65Match(host, AC65_EXCEPTIONS)) return 'DIRECT';
  if (AC65_SCOPE_ALL || ac65Match(host, AC65_PROXIED)) return AC65_CHAIN;
  return 'DIRECT';
}
`;
}

/** Строит value для chrome.proxy.settings.set() по режиму из конфига. */
export function buildProxyConfig(cfg) {
  if (cfg.mode === 'direct') {
    return { mode: 'direct' };
  }
  if (cfg.mode === 'global') {
    const server = {
      scheme: cfg.proxyScheme,
      host: cfg.proxyHost,
      port: Number(cfg.proxyPort) || 1080
    };
    return {
      mode: 'fixed_servers',
      rules: {
        singleProxy: server,
        fallbackProxy: server,
        bypassList: [...(cfg.bypass || []), ...normalizeDomains(cfg.exceptions || [])]
      }
    };
  }
  // режим 'pac' (по умолчанию)
  if (cfg.pacSource === 'url' && cfg.pacUrl) {
    // Внешний PAC-файл по URL (например, публичный «АнтиЗапрет»).
    // Chrome сам скачивает его; mandatory=false → при сбое загрузки сеть
    // откатывается на DIRECT (PacScript.url — официальное поле доков proxy API).
    return {
      mode: 'pac_script',
      pacScript: { url: cfg.pacUrl, mandatory: false }
    };
  }
  return {
    mode: 'pac_script',
    pacScript: {
      data: buildPacData(cfg),
      mandatory: false // при ошибке PAC сеть откатывается на DIRECT, а не умирает
    }
  };
}
