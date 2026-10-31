// «Антицензор» PAC — сгенерирован pac/build_pac.py
// 2026-10-31T09:09:33+00:00
// Прокси: SOCKS5 127.0.0.1:1080; резерв — DIRECT
// Список: 4 доменов; исключения: 0 доменов
// Источник списков: packs/antizensor-list.txt, packs/exceptions.txt
// Логика и источники лучших практик: docs/SOURCES.md в репозитории.
var AC65_CHAIN = 'SOCKS5 127.0.0.1:1080; DIRECT';
var AC65_SCOPE_ALL = false;
var AC65_PROXIED = ["twitter.com", "x.com", "facebook.com", "instagram.com"];
var AC65_EXCEPTIONS = [];
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
  if (h.indexOf(':') !== -1) {
    if (h === '::1' || h === '[::1]') return true;
    if (h.indexOf('fe80') === 0) return true;
    if (h.indexOf('fc') === 0 || h.indexOf('fd') === 0) return true;
    return false;
  }
  return false;
}
function ac65Match(h, list) {
  for (var i = 0; i < list.length; i++) {
    var d = list[i];
    if (d.charCodeAt(0) === 42) {
      if (shExpMatch(h, d)) return true;
    } else if (h === d) {
      return true;
    } else if (h.length > d.length + 1 &&
               h.charCodeAt(h.length - d.length - 1) === 46 &&
               h.slice(h.length - d.length) === d) {
      return true;
    }
  }
  return false;
}
function FindProxyForURL(url, host) {
  host = (host || '').toLowerCase();
  if (!host) return 'DIRECT';
  if (ac65IsPrivateHost(host)) return 'DIRECT';
  if (ac65Match(host, AC65_EXCEPTIONS)) return 'DIRECT';
  if (AC65_SCOPE_ALL || ac65Match(host, AC65_PROXIED)) return AC65_CHAIN;
  return 'DIRECT';
}
