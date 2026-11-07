'use strict';
/* ============================================================
 * CELL-65 :: cells.js - ядро плагина (MV3), зеркало скрипта
 * Доска 8x8 = 64 клетки, те же координаты a1..h8, что в c01..c08.
 * Ряды: a СРЕДА | b СЕТЬ | c СПИСКИ | d ПРОБА | e ЛОКАЛЬ | f VPN | g ПРОКСИ | h ЖИЗНЬ
 * Режимы: полуавтомат (клетка за клеткой: настройка + диагностика),
 *         автомат (авто-цикл c->d->g2 + сторож-самолечение каждые 30 мин).
 * Доктрина: ноль удалений, ноль вердиктов - только факты и координаты.
 * Радиус СПБ (59.9386, 30.3141): вне домена РФ, кольцо дистанции, затем скорость.
 * ============================================================ */

const C65 = {
  SPB: { lat: 59.9386, lon: 30.3141 },
  ROWS: { a: 'СРЕДА', b: 'СЕТЬ', c: 'СПИСКИ', d: 'ПРОБА', e: 'ЛОКАЛЬ', f: 'VPN', g: 'ПРОКСИ', h: 'ЖИЗНЬ' },
  META: {
    a1: 'браузер: версия/платформа/язык',
    a2: 'железо: ядра/память/канал',
    a3: 'время: часовой пояс/локаль',
    a4: 'запись в хранилище (тест)',
    a5: 'расширение: MV3/права/версия',
    a6: 'сеть браузера: online/rtt/downlink',
    a7: 'доска + ключевые факты',
    a8: 'отчёт среды -> storage(env)',
    b1: 'выходной IP + страна/ISP (прямой замер)',
    b2: 'дистанция выхода до СПБ + кольцо',
    b3: 'RTT до 1.1.1.1 / 8.8.8.8 (прямо, медиана x3)',
    b4: 'RTT через активный прокси Chrome',
    b5: 'текущие настройки прокси Chrome',
    b6: 'локальный gost 18080 (факт, скрипт-ряд e)',
    b7: 'доска',
    b8: 'флаг geo_home + время UTC',
    c1: 'TheSpeedX: 3 списка (http/socks4/socks5)',
    c2: 'monosans: 3 списка',
    c3: 'mmpx12: 3 списка (мусорные строки пропускаются)',
    c4: 'zloi hideip.me: 3 списка (ip:port:Страна)',
    c5: 'vakhov: 3 списка',
    c6: 'hookzof (socks5) + proxifly (протокол://ip:port)',
    c7: 'clarketm (http) + roosterkid (socks5)',
    c8: 'пул: merge + dedupe + счётчики по протоколам',
    d1: 'выборка кандидатов из пула (http/socks5/socks4)',
    d2: 'живая проба 204 через Chrome - по одному (ротация прокси)',
    d3: 'гео выживших через прокси (ipwho.is)',
    d4: 'контрольные замеры: медиана из 3',
    d5: 'отсечение РФ + кольца СПБ',
    d6: 'ВЫБОР: вне РФ, кольцо -> скорость (servers+best)',
    d7: 'доска',
    d8: 'аудит выбора: возраст/счёт вне РФ',
    e1: 'объём хранилища плагина',
    e2: 'строка upstream для gost (факт для скрипта)',
    e3: 'активный прокси Chrome (факт)',
    e4: 'здоровье активного: 204 через него',
    e5: 'статус: пул/выбор/активный',
    e6: 'рестарт: здоровье -> смена -> здоровье',
    e7: 'смена upstream: следующий по кольцу',
    e8: 'журнал (хранится в storage)',
    f1: 'факт выхода: страна/совпадение с РФ',
    f2: 'профиль VPN = скрипт, клетка f2 (data\\vpn.json)',
    f3: 'подключение VPN = скрипт, клетка f3 (rasdial)',
    f4: 'отключение VPN = скрипт, клетка f4',
    f5: 'rasdial вне досягаемости браузера; выходная страна',
    f6: 'снятие своих профилей = скрипт, клетка f6',
    f7: 'факты о встроенном VPN Windows',
    f8: 'шаблон vpn.json (текст)',
    g1: 'бэкап настроек прокси Chrome',
    g2: 'ВКЛ: применить сервер (fixed_servers)',
    g3: 'ОТКАТ: из бэкапа, иначе direct',
    g4: 'показать настройки прокси Chrome',
    g5: 'тест выхода через активный прокси',
    g6: 'winhttp = скрипт, клетка g6 (координата)',
    g7: 'исключения: <local> всегда, факт bypassList',
    g8: 'прокси-отчёт (текст)',
    h1: 'порядок настройки (полуавтомат)',
    h2: 'UNDO: direct + сторож выкл (данные не трогаются)',
    h3: 'АВТО-ЦИКЛ: ряды c и d (+g2 при флаге)',
    h4: 'СТОРОЖ: вкл/выкл (каждые 30 мин)',
    h5: 'журнал',
    h6: 'полный отчёт (текст)',
    h7: 'доска/статус',
    h8: 'шпаргалка'
  }
};

/* ---------- занятость (одна тяжёлая операция за раз) ---------- */
C65.busyGet = async function () { return C65.stGet('busy', false); };
C65.busySet = async function (v, label) { await C65.stSet({ busy: !!v, busy_label: label || '' }); };
C65.guard = async function (label, fn) {
  if (await C65.busyGet()) {
    await C65.log('!!', 'уже выполняется: ' + (await C65.stGet('busy_label', '?')) + ' - дождись финиша');
    return false;
  }
  await C65.busySet(true, label);
  try { await fn(); return true; }
  finally { await C65.busySet(false); }
};

/* ---------- хранилище ---------- */
C65.stGet = async function (key, def) {
  const o = await chrome.storage.local.get([key]);
  return (key in o) ? o[key] : def;
};
C65.stSet = function (obj) { return chrome.storage.local.set(obj); };

/* ---------- журнал ---------- */
C65.setUiHook = function (fn) { C65._uiHook = fn; };
C65.log = async function (tag, text) {
  const log = await C65.stGet('log', []);
  const t = new Date();
  const ts = ('0' + t.getHours()).slice(-2) + ':' + ('0' + t.getMinutes()).slice(-2) + ':' + ('0' + t.getSeconds()).slice(-2);
  log.push({ ts: ts, tag: tag, text: String(text) });
  while (log.length > 240) log.shift();
  await C65.stSet({ log: log });
  if (typeof C65._uiHook === 'function') { try { C65._uiHook(); } catch (e) {} }
};

/* ---------- доска ---------- */
C65.boardGet = function () { return C65.stGet('board', {}); };
C65.boardSet = async function (id, st) {
  const b = await C65.boardGet();
  b[id] = st;
  await C65.stSet({ board: b });
  if (typeof C65._uiHook === 'function') { try { C65._uiHook(); } catch (e) {} }
};
C65.boardText = async function () {
  const m = await C65.boardGet();
  const rows = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  const names = ['среда', 'сеть', 'списки', 'проба', 'локаль', 'vpn', 'прокси', 'жизнь'];
  const out = [];
  out.push('     1  2  3  4  5  6  7  8   (8x8=64; 65-я = плагин)');
  for (let r = 0; r < 8; r++) {
    let line = ' ' + rows[r] + '  ';
    for (let c = 1; c <= 8; c++) {
      const st = m[rows[r] + c] || '.';
      line += st + '  ';
    }
    line += ' ' + names[r];
    out.push(line);
  }
  out.push('     . не запускалась  o ок  x сбой  > выполняется');
  return out.join('\n');
};

/* ---------- флаги ---------- */
C65.flagGet = async function (name) {
  const f = await C65.stGet('flags', {});
  return (name in f) ? String(f[name]) : '';
};
C65.flagSet = async function (name, val) {
  const f = await C65.stGet('flags', {});
  f[name] = String(val);
  await C65.stSet({ flags: f });
};

/* ---------- запуск клетки (обёртка с отметкой на доске) ---------- */
C65.runCell = async function (id, body) {
  await C65.boardSet(id, '>');
  const t0 = performance.now();
  try {
    await body();
    await C65.boardSet(id, 'o');
    const ms = Math.round(performance.now() - t0);
    await C65.log('ok', 'клетка ' + id + ': ' + (C65.META[id] || '') + ' [' + ms + ' мс]');
    return true;
  } catch (e) {
    await C65.boardSet(id, 'x');
    await C65.log('!!', 'клетка ' + id + ': ' + (e && e.message ? e.message : e));
    return false;
  }
};
C65.runCellId = async function (id) {
  const fn = C65.CELLS[id];
  if (!fn) { await C65.log('??', 'нет клетки ' + id); return false; }
  return C65.runCell(id, fn);
};
C65.runRow = async function (row) {
  await C65.log('--', 'ряд ' + row + ' (' + (C65.ROWS[row] || '') + ')');
  for (let c = 1; c <= 8; c++) await C65.runCellId(row + c);
};

/* ---------- сеть ---------- */
C65.fetchT = function (url, timeoutMs, opts) {
  return new Promise(function (resolve, reject) {
    const ac = new AbortController();
    const to = setTimeout(function () { ac.abort(); reject(new Error('таймаут ' + timeoutMs + ' мс')); }, timeoutMs);
    const o = Object.assign({ signal: ac.signal, cache: 'no-store' }, opts || {});
    fetch(url, o).then(function (r) { clearTimeout(to); resolve(r); },
      function (e) { clearTimeout(to); reject(e); });
  });
};
C65.time204 = function (timeoutMs) {
  return new Promise(function (resolve) {
    const ac = new AbortController();
    const t0 = performance.now();
    const to = setTimeout(function () { ac.abort(); resolve(-1); }, timeoutMs);
    fetch('https://www.gstatic.com/generate_204', { signal: ac.signal, cache: 'no-store' })
      .then(function (r) {
        clearTimeout(to);
        const ms = Math.round(performance.now() - t0);
        resolve((r.status === 204 || r.status === 200) ? ms : -1);
      })
      .catch(function () { clearTimeout(to); resolve(-1); });
  });
};
/* v10: реальный трафик через текущий прокси - тело msftconnecttest по HTTPS.
 * Прозрачные фейки, которые сами отвечают 204 БЕЗ выхода в интернет, валятся здесь. */
C65.realCheck = function (timeoutMs) {
  return new Promise(function (resolve) {
    const ac = new AbortController();
    const to = setTimeout(function () { ac.abort(); resolve(false); }, timeoutMs || 7000);
    fetch('https://www.msftconnecttest.com/connecttest.txt', { signal: ac.signal, cache: 'no-store' })
      .then(function (r) {
        clearTimeout(to);
        if (!r.ok) { resolve(false); return; }
        r.text().then(function (t) { resolve(String(t).indexOf('Microsoft Connect Test') >= 0); }, function () { resolve(false); });
      })
      .catch(function () { clearTimeout(to); resolve(false); });
  });
};
/* v10: точка отсчёта - дом (b1 сам-гео), а не СПБ: универсально из любой страны */
C65.homePoint = async function () {
  const g = await C65.stGet('geo_direct', null);
  if (g && typeof g.lat === 'number' && g.cc) return { lat: g.lat, lon: g.lon, cc: g.cc, city: g.city || '?' };
  return { lat: 59.9386, lon: 30.3141, cc: 'RU', city: 'СПБ' };
};
C65.timeUrl = function (url, timeoutMs) {
  return new Promise(function (resolve) {
    const ac = new AbortController();
    const t0 = performance.now();
    const to = setTimeout(function () { ac.abort(); resolve(-1); }, timeoutMs);
    fetch(url, { signal: ac.signal, mode: 'no-cors', cache: 'no-store' })
      .then(function () { clearTimeout(to); resolve(Math.round(performance.now() - t0)); })
      .catch(function () { clearTimeout(to); resolve(-1); });
  });
};

/* ---------- гео (HTTPS, без ключа): ipwho.is -> freeipapi.com -> geojs.io ----------
 * Живая верификация при сборке v4: ipwho отвечает по-IP; freeipapi отдаёт 307 ->
 * браузер следует за редиректом сам; geojs жив, lat/lon приходят СТРОКАМИ (parseFloat).
 * ipapi.co - замок Cloudflare (факт), в цепочку не входит. */
C65.fetchGeo = async function (timeoutMs) {
  const T = timeoutMs || 8000;
  try {
    const r = await C65.fetchT('https://ipwho.is/', T);
    const j = await r.json();
    if (j && j.success !== false && j.ip) {
      return {
        ip: j.ip, cc: j.country_code || '??', country: j.country || '-',
        city: j.city || '-', lat: j.latitude, lon: j.longitude,
        isp: (j.connection && j.connection.isp) ? j.connection.isp : ((j.connection && j.connection.org) || '-')
      };
    }
  } catch (e) {}
  try {
    const r2 = await C65.fetchT('https://freeipapi.com/api/json', T);
    const j2 = await r2.json();
    if (j2 && j2.ipAddress) {
      return {
        ip: j2.ipAddress, cc: j2.countryCode || '??', country: j2.countryName || '-',
        city: j2.cityName || '-', lat: parseFloat(j2.latitude), lon: parseFloat(j2.longitude), isp: '-'
      };
    }
  } catch (e) {}
  try {
    const r3 = await C65.fetchT('https://get.geojs.io/v1/ip/geo.json', T);
    const j3 = await r3.json();
    if (j3 && j3.ip) {
      return {
        ip: j3.ip, cc: j3.country_code || '??', country: j3.country || '-',
        city: j3.city || '-', lat: parseFloat(j3.latitude), lon: parseFloat(j3.longitude),
        isp: j3.organization_name || j3.organization || '-'
      };
    }
  } catch (e) {}
  return null;
};

/* ---------- радиус СПБ ---------- */
C65.distKm = function (lat1, lon1, lat2, lon2) {
  const R = 6371.0, rad = Math.PI / 180.0;
  const p1 = lat1 * rad, p2 = lat2 * rad;
  const dp = (lat2 - lat1) * rad, dl = (lon2 - lon1) * rad;
  const a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
  const c = 2 * Math.atan2(Math.sqrt(Math.min(1, Math.max(0, a))), Math.sqrt(1 - Math.min(1, Math.max(0, a))));
  return Math.round(R * c * 10) / 10;
};
C65.ring = function (km) {
  if (km <= 500) return 1;
  if (km <= 1500) return 2;
  if (km <= 3000) return 3;
  if (km <= 6000) return 4;
  return 5;
};

/* ---------- прокси Chrome (v5: устойчивое чтение/запись) ----------
 * ФАКТ с машины пользователя (v4): settings.set() работает, а settings.get()
 * в promise-форме валил клетки b1/b3/b5/d2/g1/g4 (на доске x без текста ошибки).
 * Решение: чтение в 4 формах (promise/callback, со scope и без), ни одна не бросает;
 * итог - факт в журнале + клетка продолжает работу в доступном объёме. */
C65.proxyGet = async function () {
  const s = chrome.proxy && chrome.proxy.settings;
  if (!s || typeof s.get !== 'function') return { ok: false, err: 'chrome.proxy.settings.get недоступен (браузер без proxy API)' };
  const errs = [];
  const cbGet = function (details) {
    return new Promise(function (res) {
      try { s.get(details, function (r) { const le = chrome.runtime.lastError; res(le ? { err: le.message } : r); }); }
      catch (e) { res({ err: e && e.message ? e.message : String(e) }); }
    });
  };
  const forms = [
    { n: 'promise+scope', f: async function () { return await s.get({ scope: 'regular' }); } },
    { n: 'callback+scope', f: function () { return cbGet({ scope: 'regular' }); } },
    { n: 'promise', f: async function () { return await s.get({}); } },
    { n: 'callback', f: function () { return cbGet({}); } }
  ];
  for (const fm of forms) {
    try {
      const d = await fm.f();
      if (d && d.err) { errs.push(fm.n + ': ' + d.err); continue; }
      if (d && (d.value !== undefined || d.levelOfControl !== undefined)) {
        return { ok: true, value: (d.value !== undefined ? d.value : null), levelOfControl: d.levelOfControl || '?', form: fm.n };
      }
      errs.push(fm.n + ': пустой ответ');
    } catch (e) { errs.push(fm.n + ': ' + (e && e.message ? e.message : String(e))); }
  }
  return { ok: false, err: errs.join(' | ') };
};
C65.proxySet = async function (value) {
  const s = chrome.proxy && chrome.proxy.settings;
  if (!s || typeof s.set !== 'function') return { ok: false, err: 'chrome.proxy.settings.set недоступен (браузер без proxy API)' };
  try { await s.set({ value: value, scope: 'regular' }); return { ok: true, form: 'promise+scope' }; }
  catch (e1) {
    return await new Promise(function (res) {
      try {
        s.set({ value: value, scope: 'regular' }, function () {
          const le = chrome.runtime.lastError;
          res(le ? { ok: false, err: le.message } : { ok: true, form: 'callback+scope' });
        });
      } catch (e2) { res({ ok: false, err: (e1 && e1.message ? e1.message : String(e1)) + ' | ' + (e2 && e2.message ? e2.message : String(e2)) }); }
    });
  }
};
C65.proxyClear = async function () {
  const s = chrome.proxy && chrome.proxy.settings;
  if (!s || typeof s.clear !== 'function') return { ok: false, err: 'chrome.proxy.settings.clear недоступен' };
  try { await s.clear({ scope: 'regular' }); return { ok: true }; }
  catch (e1) {
    return await new Promise(function (res) {
      try { s.clear({ scope: 'regular' }, function () { const le = chrome.runtime.lastError; res(le ? { ok: false, err: le.message } : { ok: true }); }); }
      catch (e2) { res({ ok: false, err: (e1 && e1.message ? e1.message : String(e1)) + ' | ' + (e2 && e2.message ? e2.message : String(e2)) }); }
    });
  }
};
C65.getProxyValue = async function () {
  const r = await C65.proxyGet();
  return r.ok ? r.value : null;
};
C65.restoreProxyValue = async function (v) {
  if (v) {
    const r = await C65.proxySet(v);
    if (!r.ok) throw new Error('восстановление настроек не удалось: ' + r.err);
    return;
  }
  const rc = await C65.proxyClear();
  if (!rc.ok) throw new Error('сброс настроек (clear) не удался: ' + rc.err);
};
C65.validHostPort = function (host, port) {
  const h = String(host == null ? '' : host).trim();
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(h);
  if (!m) return false;
  if (parseInt(m[1], 10) > 255 || parseInt(m[2], 10) > 255 || parseInt(m[3], 10) > 255 || parseInt(m[4], 10) > 255) return false;
  const ps = String(port == null ? '' : port).trim();
  if (!/^\d{1,5}$/.test(ps)) return false;
  const p = parseInt(ps, 10);
  return p >= 1 && p <= 65535;
};

/* ---- v2.3.0: меритократия (score-леджер в storage) ----
 * лидер копит очки (+10 за живую пробу), старение x0.9 за авто-цикл,
 * сбой = x0.3 ('Федя в пень') - следующий по очкам занимает место. */
C65.scoreOf = function (map, host, port) {
  const k = String(host) + ':' + String(port);
  return (map && typeof map[k] === 'number') ? map[k] : 50;
};
C65.scoreAdj = async function (host, port, delta, mult) {
  try {
    const map = (await C65.stGet('score', {})) || {};
    const k = String(host) + ':' + String(port);
    let v = (typeof map[k] === 'number') ? map[k] : 50;
    v = (typeof mult === 'number' && mult >= 0) ? v * mult : v + delta;
    if (v > 1000) v = 1000;
    map[k] = Math.round(v * 10) / 10;
    await C65.stSet({ score: map });
    return map[k];
  } catch (e) { return null; }
};
C65.scoreDecay = async function () {
  try {
    const map = (await C65.stGet('score', {})) || {};
    const out = {};
    for (const k of Object.keys(map)) {
      const v = Math.round(map[k] * 90) / 100;
      if (v >= 3) out[k] = v;
    }
    await C65.stSet({ score: out });
  } catch (e) {}
};
C65.schemeOf = function (proto) {
  const p = String(proto || 'http').toLowerCase();
  if (p === 'socks5') return 'socks5';
  if (p === 'socks4') return 'socks4';
  return 'http';
};
C65.bypassList = async function () {
  const extra = await C65.stGet('extra_bypass', []);
  return ['<local>'].concat(Array.isArray(extra) ? extra : []);
};
C65.setProxyFixed = async function (host, port, proto) {
  if (!C65.validHostPort(host, port)) throw new Error('некорректный адрес прокси: ' + host + ':' + port + ' (в Chrome не применён)');
  const value = {
    mode: 'fixed_servers',
    rules: { singleProxy: { scheme: C65.schemeOf(proto), host: String(host), port: parseInt(port, 10) }, bypassList: await C65.bypassList() }
  };
  const r = await C65.proxySet(value);
  if (!r.ok) throw new Error('chrome.proxy.set (fixed_servers) не удался: ' + r.err);
};
C65.setProxyDirect = async function () {
  const r = await C65.proxySet({ mode: 'direct' });
  if (!r.ok) throw new Error('chrome.proxy.set (direct) не удался: ' + r.err);
};
C65.badgeOf = function (ring) {
  const r = parseInt(ring, 10);
  return (r && r !== 9) ? ('R' + r) : 'R?';
};
C65.applyServerObj = async function (s) {
  if (!s || !C65.validHostPort(s.host, s.port)) { await C65.log('!!', 'сервер с некорректным адресом не применяется: ' + (s && s.host) + ':' + (s && s.port)); return false; }
  await C65.setProxyFixed(s.host, s.port, s.proto);
  const act = { host: String(s.host), port: parseInt(s.port, 10), proto: String(s.proto || 'http'), ring: s.ring || 9 };
  await C65.stSet({ active: act });
  try {
    chrome.action.setBadgeText({ text: C65.badgeOf(act.ring) });
    chrome.action.setBadgeBackgroundColor({ color: '#0e7490' });
  } catch (e) {}
  await C65.log('ok', 'прокси Chrome ВКЛ: ' + act.proto + ' ' + act.host + ':' + act.port + ' (R' + act.ring + ')');
  return true;
};
C65.setDirect = async function (silent) {
  await C65.setProxyDirect();
  await C65.stSet({ active: null });
  try { chrome.action.setBadgeText({ text: '' }); } catch (e) {}
  if (!silent) await C65.log('ok', 'прокси Chrome ВЫКЛ (direct)');
};

/* смена на следующий по списку (зеркало e7/сторож) */
C65.switchNext = async function () {
  let servers = await C65.stGet('servers', []);
  const act = await C65.stGet('active', null);
  if (!servers.length) { await C65.log('!!', 'запасных нет - координата: ряд d (выбор ещё не делался)'); return false; }
  if (act) { await C65.scoreAdj(act.host, act.port, 0, 0.3); await C65.log('i', 'меритократия: активный понижен x0.3, место занимает следующий по очкам'); }
  // v11: вердикты пробы + карантин - ЖИЗНЬ больше не ретраит проваливших d2
  // (живая жалоба 6ORMAN: «второй раз подключается к тому, что не работало»).
  // Карантин 30 мин - зеркало PS e7 (cooldown.tsv): проваливший upstream туда и уходит;
  // 407-узлы пробы исключаются всегда; протухшие записи карантина выкидываются.
  const now = Date.now();
  const cd = await C65.stGet('cooldown', {});
  for (const k of Object.keys(cd)) { if (cd[k] < now - 30 * 60 * 1000) delete cd[k]; }
  if (act) {
    const ck = act.host + ':' + act.port;
    if (cd[ck] === undefined) await C65.log('i', 'карантин 30 мин на ' + ck + ' (здоровье потеряно)');
    cd[ck] = now;
  }
  await C65.stSet({ cooldown: cd });
  const auth = await C65.stGet('auth407', []);
  const authSet = {};
  for (const a of auth) authSet[a] = 1;
  const pre = servers.length;
  servers = servers.filter(function (s) {
    return authSet[s.host + '|' + s.port] !== 1 && cd[s.host + ':' + s.port] === undefined;
  });
  if (servers.length < pre) await C65.log('i', 'ЖИЗНЬ: из запасных исключены 407/карантин: ' + (pre - servers.length) + ' (было ' + pre + ', осталось ' + servers.length + ')');
  if (!servers.length) {
    servers = await C65.stGet('servers', []);
    const actK = act ? (act.host + ':' + act.port) : '';
    servers = servers.filter(function (s) { return (s.host + ':' + s.port) !== actK; });
    if (servers.length) await C65.log('i', 'все запасные в карантине/407 - использую полный список (лучше попытка, чем простой)');
  }
  const map = await C65.stGet('score', {});
  servers = servers.slice().sort(function (a, b) { return C65.scoreOf(map, b.host, b.port) - C65.scoreOf(map, a.host, a.port); });
  const next = servers[0];
  if (!next) { await C65.log('!!', 'список серверов пуст - координата: ряд d'); return false; }
  if (act && String(next.host) === String(act.host) && parseInt(next.port, 10) === parseInt(act.port, 10)) {
    await C65.log('!!', 'запасных нет (активный = лидер по очкам) - координата: ряд d');
    return false;
  }
  return C65.applyServerObj(next);
};

/* ---------- списки: 9 источников, те же URL, что в скрипте ---------- */
C65.SOURCES = {
  thespeedx: [['http', 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt'], ['socks4', 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks4.txt'], ['socks5', 'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt']],
  monosans: [['http', 'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt'], ['socks4', 'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks4.txt'], ['socks5', 'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt']],
  mmpx12: [['http', 'https://raw.githubusercontent.com/mmpx12/proxy-list/master/http.txt'], ['socks4', 'https://raw.githubusercontent.com/mmpx12/proxy-list/master/socks4.txt'], ['socks5', 'https://raw.githubusercontent.com/mmpx12/proxy-list/master/socks5.txt']],
  zloi: [['http', 'https://raw.githubusercontent.com/zloi-user/hideip.me/main/http.txt'], ['socks4', 'https://raw.githubusercontent.com/zloi-user/hideip.me/main/socks4.txt'], ['socks5', 'https://raw.githubusercontent.com/zloi-user/hideip.me/main/socks5.txt']],
  vakhov: [['http', 'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/http.txt'], ['socks4', 'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/socks4.txt'], ['socks5', 'https://raw.githubusercontent.com/vakhov/fresh-proxy-list/master/socks5.txt']],
  hookzof: [['socks5', 'https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt']],
  proxifly: [['all', 'https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/all/data.txt']],
  roosterkid: [['socks5', 'https://raw.githubusercontent.com/roosterkid/openproxylist/main/SOCKS5_RAW.txt'], ['socks4', 'https://raw.githubusercontent.com/roosterkid/openproxylist/main/SOCKS4_RAW.txt']]
};
C65.parseLine = function (line, fileProto) {
  const m = /^(?:(https?|socks[45]):\/\/)?(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})/.exec(String(line).trim());
  if (!m) return null;
  let proto = m[1] || fileProto || '';
  if (proto === 'https') proto = 'http';
  if (proto !== 'http' && proto !== 'socks4' && proto !== 'socks5') return null;
  return proto + '|' + m[2] + '|' + m[3];
};

/* ---------- v11: чистка Cloudflare-мусора ----------
 * Официальные IPv4-сети Cloudflare (cloudflare.com/ips-v4, сфетчено 07.11.2026):
 * прокси там быть не может - это CDN-грани и страницы ошибок 502/1015,
 * которые сырые списки иногда отдают строками, похожими на "ip:порт".
 * Зеркало в PS: Test-CfIp в lib65.psm1. */
C65.CF_NETS = (function () {
  const raw = ['173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22', '141.101.64.0/18', '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20', '197.234.240.0/22', '198.41.128.0/17', '162.158.0.0/15', '104.16.0.0/13', '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22'];
  return raw.map(function (cidr) {
    const p = cidr.split('/'), q = p[0].split('.'), bits = parseInt(p[1], 10);
    const n = (((parseInt(q[0], 10) << 24) | (parseInt(q[1], 10) << 16) | (parseInt(q[2], 10) << 8) | parseInt(q[3], 10)) >>> 0);
    const mask = bits === 0 ? 0 : ((0xFFFFFFFF << (32 - bits)) >>> 0);
    return [n & mask, mask];
  });
})();
C65.isCfIp = function (ipStr) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(String(ipStr || ''));
  if (!m) return false;
  const n = (((parseInt(m[1], 10) << 24) | (parseInt(m[2], 10) << 16) | (parseInt(m[3], 10) << 8) | parseInt(m[4], 10)) >>> 0);
  for (let i = 0; i < C65.CF_NETS.length; i++) { if ((n & C65.CF_NETS[i][1]) === C65.CF_NETS[i][0]) return true; }
  return false;
};
C65.fetchSource = async function (srcId) {
  const files = C65.SOURCES[srcId];
  if (!files) return;
  const bySrc = await C65.stGet('poolBySrc', {});
  const key = srcId;
  const items = [];
  const seen = {};
  let bad = 0, got = 0;
  for (const f of files) {
    const proto = f[0], url = f[1];
    let txt = '';
    try {
      const r = await C65.fetchT(url, 20000);
      txt = await r.text();
      got++;
    } catch (e) {
      await C65.log('!!', 'источник ' + srcId + '/' + proto + ': загрузка не удалась (сеть/код)');
      continue;
    }
    let n = 0, ok = 0, cf = 0;
    for (const ln of txt.split('\n')) {
      n++;
      const it = C65.parseLine(ln, proto === 'all' ? '' : proto);
      if (!it) { if (ln.trim() !== '') bad++; continue; }
      // v11: Cloudflare-мусор отсекается сразу при разборе источника
      if (C65.isCfIp(it.split('|')[1])) { cf++; continue; }
      if (!seen[it]) { seen[it] = 1; items.push(it); ok++; }
    }
    if (cf > 0) bad += cf;
    await C65.log('i', 'источник ' + srcId + '/' + proto + ': ' + ok + ' записей (строк ' + n + (cf ? ', CF-мусор: ' + cf : '') + ')');
  }
  bySrc[key] = { n: items.length, bad: bad, ts: new Date().toISOString().slice(0, 19).replace('T', ' '), items: items };
  await C65.stSet({ poolBySrc: bySrc });
  return { got: got, total: files.length, items: items.length };
};
C65.mergePool = async function () {
  const bySrc = await C65.stGet('poolBySrc', {});
  const seen = {};
  const pool = [];
  const cnt = { http: 0, socks4: 0, socks5: 0 };
  let bad = 0, cfCut = 0;
  for (const k of Object.keys(bySrc)) {
    bad += (bySrc[k].bad || 0);
    for (const it of bySrc[k].items) {
      if (seen[it]) continue;
      seen[it] = 1;
      // v11: защита от старых пулов в хранилище - Cloudflare-IP до пробы не доживают
      if (C65.isCfIp(it.split('|')[1])) { cfCut++; continue; }
      pool.push(it);
      const p = it.split('|')[0];
      if (cnt[p] !== undefined) cnt[p]++;
    }
  }
  if (cfCut > 0) await C65.log('i', 'из пула исключены Cloudflare-IP: ' + cfCut + ' (прокси в сетях CF быть не может)');
  while (pool.length > 6000) pool.pop();
  const ts = new Date().toISOString().slice(0, 19).replace('T', ' ');
  await C65.stSet({ pool: pool, ts_pool: ts });
  await C65.log('ok', 'пул: ' + cnt.http + ' http, ' + cnt.socks4 + ' socks4, ' + cnt.socks5 + ' socks5 (мусорных строк: ' + bad + ')');
  return pool.length;
};

/* ---------- проба ---------- */
C65.sampleFromPool = async function () {
  const pool = await C65.stGet('pool', []);
  if (!pool.length) return [];
  const auth = await C65.stGet('auth407', []);
  const take = { http: 8, socks5: 8, socks4: 4 };
  const out = [];
  for (const p of Object.keys(take)) {
    let sub = pool.filter(function (x) { return x.indexOf(p + '|') === 0; });
    if (auth.length) {
      const before = sub.length;
      sub = sub.filter(function (x) { const z = x.split('|'); return auth.indexOf((z[1] || '') + '|' + (z[2] || '')) < 0; });
      if (sub.length < before) await C65.log('i', 'из выборки ' + p + ' исключены 407-узлы прошлых проб: ' + (before - sub.length));
    }
    const beforeCf = sub.length;
    sub = sub.filter(function (x) { return !C65.isCfIp(x.split('|')[1]); });
    if (sub.length < beforeCf) await C65.log('i', 'из выборки ' + p + ' исключены Cloudflare-IP: ' + (beforeCf - sub.length));
    if (!sub.length) { await C65.log('i', 'выборка ' + p + ': пусто'); continue; }
    for (let i = sub.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = sub[i]; sub[i] = sub[j]; sub[j] = t; }
    const n = Math.min(take[p], sub.length);
    for (let k = 0; k < n; k++) out.push(sub[k]);
    await C65.log('i', 'выборка ' + p + ': ' + n + ' из ' + sub.length);
  }
  await C65.stSet({ sample: out, ts_sample: new Date().toISOString().slice(0, 19).replace('T', ' ') });
  return out;
};
/* ротация chrome.proxy по кандидатам; возвращает собранные факты */
C65.rotateProbe = async function (items, fn, timeoutMs) {
  const pr = await C65.proxyGet();
  const saved = pr.ok ? pr.value : null;
  if (!pr.ok) await C65.log('!!', 'чтение настроек перед ротацией не удалось (' + pr.err + ') - ротация идёт, в конце сброс clear (system)');
  const out = [];
  try {
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      const q = it.proto ? it : (function () { const z = it.split('|'); return { proto: z[0], host: z[1], port: z[2] }; })();
      if (!C65.validHostPort(q.host, q.port)) { await C65.log('!!', 'кандидат ' + (i + 1) + '/' + items.length + ' с некорректным адресом пропущен: ' + q.host + ':' + q.port); continue; }
      await C65.setProxyFixed(q.host, q.port, q.proto);
      const r = await fn(q, i);
      if (r) out.push(r);
    }
  } finally {
    try { await C65.restoreProxyValue(saved); }
    catch (e) { await C65.log('!!', 'восстановление после ротации не удалось: ' + (e && e.message ? e.message : e) + ' | координата: g3 (откат) или кнопка DIRECT'); }
  }
  return out;
};
C65.quickProbeAll = async function (sample) {
  const survivors = [];
  const authHits = [];
  let dead = 0;
  await C65.rotateProbe(sample, async function (q, idx) {
    const kills0 = C65.authKills || 0;
    const ms = await C65.time204(4500);
    const kills1 = C65.authKills || 0;
    if (ms < 0 && kills1 > kills0) {
      authHits.push(q.host + '|' + q.port);
      await C65.log('i', 'проба ' + (idx + 1) + '/' + sample.length + ' ' + q.host + ':' + q.port + ' -> 407 (требует авторизацию) - в чёрный список, проба время на него больше не тратит');
      return false;
    }
    if (ms >= 0) {
      const real = await C65.realCheck(7000);
      if (!real) {
        dead++;
        await C65.log('i', 'проба ' + (idx + 1) + '/' + sample.length + ' ' + q.host + ':' + q.port + ' -> 204 за ' + ms + ' мс, но реальный трафик не проходит - ПОЛУМЁРТВ, в живые не берём');
        return false;
      }
      survivors.push({ proto: q.proto, host: q.host, port: q.port, ms: ms });
      C65.scoreAdj(q.host, q.port, 10);
      await C65.log('ok', 'проба ' + (idx + 1) + '/' + sample.length + ' ' + q.host + ':' + q.port + ' -> 204 за ' + ms + ' мс + реальный трафик OK');
      return true;
    }
    dead++;
    await C65.log('i', 'проба ' + (idx + 1) + '/' + sample.length + ' ' + q.host + ':' + q.port + ' -> нет ответа');
    return false;
  }, 4500);
  await C65.stSet({ survivors: survivors });
  if (authHits.length) {
    const old = await C65.stGet('auth407', []);
    await C65.stSet({ auth407: old.concat(authHits).slice(-500) });
  }
  await C65.log('ok', 'итог пробы: живые ' + survivors.length + ' | 407: ' + authHits.length + ' | мертвы/полумертвы: ' + dead + ' (из ' + sample.length + ', ротация по одному, Chrome)');
  return survivors;
};
C65.geoSurvivors = async function (survivors) {
  const cap = survivors.slice(0, 12);
  const home = await C65.homePoint();
  const geotable = [];
  const res = await C65.rotateProbe(cap, async function (q) {
    const t0 = performance.now();
    const g = await C65.fetchGeo(8000);
    const ms = Math.round(performance.now() - t0);
    if (g) {
      const km = (typeof g.lat === 'number') ? C65.distKm(home.lat, home.lon, g.lat, g.lon) : -1;
      geotable.push({ proto: q.proto, host: q.host, port: q.port, ms: ms, cc: g.cc, country: g.country, city: g.city, lat: g.lat, lon: g.lon, isp: g.isp, dist_km: km, ring: km >= 0 ? C65.ring(km) : 9 });
      await C65.log('i', 'гео: ' + q.host + ':' + q.port + ' -> ' + g.cc + '/' + g.city + ' | ' + (km >= 0 ? (km + ' км от дома (' + home.cc + '), R' + C65.ring(km)) : 'R?') + ' | ' + ms + ' мс');
      return true;
    }
    geotable.push({ proto: q.proto, host: q.host, port: q.port, ms: q.ms, cc: '??', country: '-', city: '-', lat: null, lon: null, isp: '-', dist_km: -1, ring: 9 });
    await C65.log('!!', 'гео: ' + q.host + ':' + q.port + ' -> не ответил (R?)');
    return false;
  });
  await C65.stSet({ geotable: geotable });
  return geotable;
};
C65.controlMeasure = async function (geotable) {
  const top = geotable.slice().sort(function (a, b) { return (a.ring - b.ring) || (a.ms - b.ms); }).slice(0, 8);
  const res = await C65.rotateProbe(top, async function (q) {
    const a = await C65.time204(3500);
    const b = await C65.time204(3500);
    const vals = [q.ms, a, b].filter(function (x) { return x >= 0; }).sort(function (x, y) { return x - y; });
    if (vals.length >= 2) { q.ms = vals[Math.floor((vals.length - 1) / 2)]; }
    await C65.log('i', 'контроль ' + q.host + ':' + q.port + ' -> медиана ' + q.ms + ' мс (n=' + vals.length + ')');
    return true;
  });
  await C65.stSet({ geotable: top });
  return top;
};
C65.rankAndFilter = async function (geotable) {
  const home = await C65.homePoint();
  const hc = home.cc || 'RU';
  const own = geotable.filter(function (g) { return g.cc === hc; });
  const keep = geotable.filter(function (g) { return g.cc !== hc; });
  keep.sort(function (a, b) { return (a.ring - b.ring) || (a.ms - b.ms); });
  await C65.stSet({ ranked: keep });
  await C65.log('ok', 'гео: ' + geotable.length + ' | вне дом-страны (' + hc + '): ' + keep.length + ' | своих отфильтровано: ' + own.length + ' | гео не ответил: ' + geotable.filter(function (g) { return g.cc === '??'; }).length);
  const r1 = keep.filter(function (g) { return g.ring === 1; }).length;
  if (r1) await C65.log('i', 'ближний класс (до 500 км от дома): ' + r1 + ' шт');
  return keep;
};
C65.makeChoice = async function (ranked) {
  if (!ranked.length) { await C65.log('!!', 'вне дом-страны живых: 0 - координата: повторить ряды c и d'); return null; }
  const list = ranked.map(function (g, i) {
    return { rank: i + 1, host: g.host, port: g.port, proto: g.proto, country: g.country, cc: g.cc, city: g.city, dist_km: g.dist_km, ring: g.ring, http_s: Math.round(g.ms) / 1000 };
  });
  const best = list[0];
  const obj = {
    ts: new Date().toISOString().slice(0, 19).replace('T', ' '),
    policy: 'radius SPB 59.9386,30.3141: outside RF, ring asc, http_s asc',
    proto: best.proto, host: best.host, port: best.port,
    http_s: best.http_s, cc: best.cc, country: best.country, city: best.city,
    dist_km: best.dist_km, ring: best.ring,
    top8: list.slice(0, 8).map(function (s) { return s.proto + '|' + s.host + '|' + s.port + '|' + s.http_s.toFixed(2) + '|' + s.cc + '|R' + s.ring + '|' + s.dist_km + 'km'; })
  };
  await C65.stSet({ servers: list.slice(0, 100), best: obj, ts_best: obj.ts });
  await C65.log('ok', 'выбор (радиус СПБ): R' + best.ring + ' ' + best.proto + ' ' + best.host + ':' + best.port + ' | ' + best.country + '/' + best.city + ' | ' + best.dist_km + ' км | 204 за ' + best.http_s.toFixed(2) + ' c');
  await C65.log('i', 'вне РФ в списке: ' + list.length + ' | ручное переключение: вкладка СЕРВЕРЫ');
  return obj;
};

/* ---------- 64 клетки (координаты = скрипт) ---------- */
C65.CELLS = {
  /* --- ряд A: СРЕДА --- */
  a1: async function () {
    const ua = navigator.userAgent;
    const mv = ua.match(/Chrome\/([\d.]+)/);
    await C65.log('i', 'браузер: Chrome ' + (mv ? mv[1] : '?') + ' | платформа: ' + navigator.platform);
    await C65.log('i', 'язык: ' + navigator.language + (navigator.languages ? (' | все: ' + navigator.languages.slice(0, 4).join(',')) : ''));
  },
  a2: async function () {
    const c = navigator.connection || {};
    await C65.log('i', 'ядер: ' + (navigator.hardwareConcurrency || '?') + ' | память (прибл.): ' + (navigator.deviceMemory ? (navigator.deviceMemory + ' ГБ') : 'нет данных'));
    await C65.log('i', 'канал: ' + (c.effectiveType || '?') + ' | rtt ~' + (c.rtt !== undefined ? c.rtt : '?') + ' мс | downlink ~' + (c.downlink !== undefined ? c.downlink : '?') + ' Мбит/с');
  },
  a3: async function () {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || '?';
    await C65.log('i', 'зона: ' + tz + ' | локаль: ' + navigator.language);
    await C65.log('i', 'время: ' + new Date().toLocaleString() + ' | UTC: ' + new Date().toUTCString());
  },
  a4: async function () {
    const k = 'writetest';
    const prev = await C65.stGet(k, 0);
    await C65.stSet({ writetest: prev + 1 });
    const now = await C65.stGet(k, 0);
    if (now > prev) await C65.log('ok', 'запись в chrome.storage.local: работает (счётчик ' + now + ')');
    else throw new Error('запись не подтвердилась');
  },
  a5: async function () {
    const m = chrome.runtime.getManifest();
    await C65.log('i', 'расширение: ' + m.name + ' v' + m.version + ' | manifest_version: ' + m.manifest_version);
    await C65.log('i', 'права: ' + m.permissions.join(', ') + ' | фоновый сервис-воркер: ' + (m.background ? m.background.service_worker : 'нет'));
  },
  a6: async function () {
    const c = navigator.connection || {};
    await C65.log('i', 'online: ' + navigator.onLine + ' | effectiveType: ' + (c.effectiveType || '?') + ' | saveData: ' + (c.saveData !== undefined ? c.saveData : '?'));
  },
  a7: async function () {
    await C65.log('i', '\n' + (await C65.boardText()));
    await C65.log('i', await C65.keyFactsText());
  },
  a8: async function () {
    const env = {
      ts: new Date().toISOString().slice(0, 19).replace('T', ' '),
      ua: navigator.userAgent,
      lang: navigator.language,
      tz: Intl.DateTimeFormat().resolvedOptions().timeZone || '',
      cores: navigator.hardwareConcurrency || 0,
      mem_gb: navigator.deviceMemory || 0,
      online: navigator.onLine
    };
    await C65.stSet({ env: env });
    await C65.log('ok', 'факты среды -> storage(env)');
  },

  /* --- ряд B: СЕТЬ --- */
  b1: async function () {
    const pr = await C65.proxyGet();
    const saved = pr.ok ? pr.value : null;
    const had = pr.ok && saved && saved.mode !== 'direct';
    if (!pr.ok) await C65.log('!!', 'чтение настроек прокси не удалось (' + pr.err + ') - замер идёт в текущем режиме, без смены режима');
    if (had) await C65.setProxyDirect();
    try {
      const g = await C65.fetchGeo(9000);
      if (!g) throw new Error('нет ответа гео-сервиса (координата: интернет/firewall)');
      await C65.log('i', 'прямой выходной IP: ' + g.ip + ' | ' + g.country + ' (' + g.cc + ') | ' + g.city + ' | ISP: ' + g.isp);
      await C65.flagSet('geo_home', g.cc + '/' + g.city);
      await C65.stSet({ geo_direct: g });
    } finally {
      if (had) { try { await C65.restoreProxyValue(saved); } catch (e) { await C65.log('!!', 'восстановление после замера: ' + (e && e.message ? e.message : e)); } }
    }
  },
  b2: async function () {
    const g = await C65.stGet('geo_direct', null);
    if (!g || typeof g.lat !== 'number') { await C65.log('!!', 'гео выхода нет (координата: b1)'); return; }
    const home = await C65.homePoint();
    const km = C65.distKm(home.lat, home.lon, g.lat, g.lon);
    await C65.log('i', 'дистанция выхода до дома (' + home.cc + '): ' + km + ' км | класс дальности R' + C65.ring(km));
  },
  b3: async function () {
    const pr = await C65.proxyGet();
    const saved = pr.ok ? pr.value : null;
    const had = pr.ok && saved && saved.mode !== 'direct';
    if (!pr.ok) await C65.log('!!', 'чтение настроек прокси не удалось (' + pr.err + ') - RTT замер идёт в текущем режиме');
    if (had) await C65.setProxyDirect();
    try {
      for (const t of [['1.1.1.1', 'https://1.1.1.1/'], ['8.8.8.8', 'https://8.8.8.8/']]) {
        const ms = [];
        for (let i = 0; i < 3; i++) { const v = await C65.timeUrl(t[1], 2500); if (v >= 0) ms.push(v); }
        if (ms.length) { ms.sort(function (a, b) { return a - b; }); await C65.log('i', 'база ' + t[0] + ' -> медиана ' + ms[Math.floor((ms.length - 1) / 2)] + ' мс (n=' + ms.length + ')'); }
        else await C65.log('!!', 'база ' + t[0] + ' -> нет ответа');
      }
    } finally {
      if (had) { try { await C65.restoreProxyValue(saved); } catch (e) { await C65.log('!!', 'восстановление после замера: ' + (e && e.message ? e.message : e)); } }
    }
  },
  b4: async function () {
    const act = await C65.stGet('active', null);
    if (!act) { await C65.log('i', 'прокси Chrome не включён - замер идёт напрямую (координата: g2)'); return; }
    const ms = [];
    for (let i = 0; i < 3; i++) { const v = await C65.time204(5000); if (v >= 0) ms.push(v); }
    if (ms.length) { ms.sort(function (a, b) { return a - b; }); await C65.log('i', 'через ' + act.host + ':' + act.port + ' -> медиана ' + ms[Math.floor((ms.length - 1) / 2)] + ' мс (n=' + ms.length + ')'); }
    else await C65.log('!!', 'через ' + act.host + ':' + act.port + ' -> 204 не пришёл');
  },
  b5: async function () {
    const r = await C65.proxyGet();
    if (!r.ok) { await C65.log('!!', 'настройки прокси Chrome не читаются: ' + r.err + ' | сетевые факты без этого чтения: b4 (RTT), g5 (выход)'); return; }
    const v = r.value;
    const mode = v ? v.mode : '(по умолчанию: system)';
    await C65.log('i', 'chrome.proxy: mode=' + mode + ' | контроль: ' + r.levelOfControl + ' | форма чтения: ' + r.form);
    if (v && v.rules && v.rules.singleProxy) await C65.log('i', 'singleProxy: ' + v.rules.singleProxy.scheme + ' ' + v.rules.singleProxy.host + ':' + v.rules.singleProxy.port);
  },
  b6: async function () {
    const v = await C65.timeUrl('http://127.0.0.1:18080/', 2500);
    if (v >= 0) await C65.log('ok', 'локальный gost 127.0.0.1:18080 (HTTP): отвечает [' + v + ' мс] (это ряд e скрипта)');
    else await C65.log('i', 'локальный gost 18080: не отвечает (норма, если скриптовый ряд e не запускался; 18081 SOCKS5 проверяет клетка e4 скрипта)');
  },
  b7: async function () { await C65.log('i', '\n' + (await C65.boardText())); },
  b8: async function () {
    const f = await C65.flagGet('geo_home');
    await C65.log('i', 'флаг geo_home: ' + (f || 'не установлен (координата: b1)') + ' | UTC: ' + new Date().toUTCString());
  },

  /* --- ряд C: СПИСКИ --- */
  c1: async function () { await C65.fetchSource('thespeedx'); },
  c2: async function () { await C65.fetchSource('monosans'); },
  c3: async function () { await C65.log('i', 'mmpx12: в файлах бывают служебные строки - парсер пропускает всё, что не ip:port'); await C65.fetchSource('mmpx12'); },
  c4: async function () { await C65.log('i', 'zloi hideip.me: формат ip:port:Страна - парсер берёт ip и порт'); await C65.fetchSource('zloi'); },
  c5: async function () { await C65.fetchSource('vakhov'); },
  c6: async function () { await C65.fetchSource('hookzof'); await C65.log('i', 'proxifly: формат протокол://ip:port'); await C65.fetchSource('proxifly'); },
  c7: async function () { await C65.fetchSource('clarketm'); await C65.fetchSource('roosterkid'); },
  c8: async function () { await C65.mergePool(); },

  /* --- ряд D: ПРОБА И ВЫБОР (радиус СПБ) --- */
  d1: async function () {
    const s = await C65.sampleFromPool();
    if (!s.length) { await C65.log('!!', 'пул пуст - координата: ряд c (клетка c8)'); return; }
    await C65.log('i', 'выборка всего: ' + s.length + ' кандидатов');
  },
  d2: async function () {
    const s = await C65.stGet('sample', []);
    if (!s.length) { await C65.log('!!', 'sample нет - координата: d1'); return; }
    await C65.log('i', 'проба 204 через Chrome по одному: ' + s.length + ' шт, таймаут 4.5 с (на время пробы прокси Chrome переключается - факты восстановятся сами)');
    await C65.quickProbeAll(s);
  },
  d3: async function () {
    const sv = await C65.stGet('survivors', []);
    if (!sv.length) { await C65.log('!!', 'выживших нет - координата: d2'); return; }
    await C65.log('i', 'гео выживших через их же прокси: ' + Math.min(12, sv.length) + ' шт | точка отсчёта: СПБ 59.9386,30.3141');
    await C65.geoSurvivors(sv);
  },
  d4: async function () {
    const gt = await C65.stGet('geotable', []);
    if (!gt.length) { await C65.log('!!', 'geotable нет - координата: d3'); return; }
    await C65.controlMeasure(gt);
  },
  d5: async function () {
    const gt = await C65.stGet('geotable', []);
    if (!gt.length) { await C65.log('!!', 'geotable нет - координата: d3'); return; }
    await C65.rankAndFilter(gt);
  },
  d6: async function () {
    const r = await C65.stGet('ranked', []);
    if (!r.length) { await C65.log('!!', 'ранжированных нет - координата: d5'); return; }
    await C65.makeChoice(r);
  },
  d7: async function () { await C65.log('i', '\n' + (await C65.boardText())); await C65.log('i', await C65.keyFactsText()); },
  d8: async function () {
    const b = await C65.stGet('best', null);
    if (!b) { await C65.log('i', 'аудит: выбор ещё не делался (координата: d6)'); return; }
    const ts = await C65.stGet('ts_best', '');
    const ageH = ts ? Math.round((Date.now() - new Date(ts.replace(' ', 'T')).getTime()) / 360000) / 10 : 0;
    await C65.log('i', 'аудит выбора: ' + b.proto + ' ' + b.host + ':' + b.port + ' | R' + b.ring + ' ' + b.cc + ' ' + b.dist_km + ' км | ' + (b.http_s ? b.http_s.toFixed ? b.http_s.toFixed(2) : b.http_s : '?') + ' c | возраст ~' + ageH + ' ч | топ8: ' + (b.top8 || []).length);
    const sv = await C65.stGet('servers', []);
    await C65.log('i', 'вне РФ в списке: ' + sv.length + ' (вкладка СЕРВЕРЫ)');
    if (ageH > 24) await C65.log('i', 'аудит: выбор старше 24ч - координата: авто-цикл (h3) или ряды c и d');
  },

  /* --- ряд E: ЛОКАЛЬ (хранилище плагина) --- */
  e1: async function () {
    let bytes = 0;
    try { bytes = await chrome.storage.local.getBytesInUse(null); } catch (e) {}
    const o = await chrome.storage.local.get(null);
    await C65.log('i', 'хранилище: ' + Object.keys(o).length + ' ключей, ~' + Math.round(bytes / 1024) + ' КБ');
  },
  e2: async function () {
    const b = await C65.stGet('best', null);
    if (!b) { await C65.log('!!', 'выбора нет - координата: d6'); return; }
    await C65.log('ok', 'upstream для gost (факт для скрипта, клетка e2): ' + b.proto + '://' + b.host + ':' + b.port);
  },
  e3: async function () {
    const act = await C65.stGet('active', null);
    if (act) await C65.log('i', 'активный прокси Chrome: ' + act.proto + ' ' + act.host + ':' + act.port + ' (R' + act.ring + ')');
    else await C65.log('i', 'активный прокси Chrome: нет (direct)');
  },
  e4: async function () {
    const act = await C65.stGet('active', null);
    if (!act) { await C65.flagSet('proxy_ok', '0'); await C65.log('i', 'здоровье: прокси не включён (координата: g2)'); return; }
    const ms = await C65.time204(6000);
    if (ms >= 0) { await C65.flagSet('proxy_ok', '1'); await C65.log('ok', 'здоровье: ' + act.host + ':' + act.port + ' -> 204 за ' + ms + ' мс'); }
    else { await C65.flagSet('proxy_ok', '0'); await C65.log('!!', 'здоровье: ' + act.host + ':' + act.port + ' -> нет 204 (координата: e7 смена upstream)'); }
  },
  e5: async function () {
    const pool = await C65.stGet('pool', []);
    const sv = await C65.stGet('servers', []);
    const act = await C65.stGet('active', null);
    const ts = await C65.stGet('ts_pool', '');
    await C65.log('i', 'пул: ' + pool.length + (ts ? (' (' + ts + ')') : '') + ' | список серверов: ' + sv.length + ' | активный: ' + (act ? act.host + ':' + act.port : 'direct'));
  },
  e6: async function () {
    await C65.CELLS.e4();
    const ok = await C65.flagGet('proxy_ok');
    if (ok !== '1') {
      await C65.log('--', 'здоровье потеряно -> смена upstream (e7)');
      await C65.CELLS.e7();
      await C65.CELLS.e4();
    }
  },
  e7: async function () { await C65.switchNext(); },
  e8: async function () {
    const log = await C65.stGet('log', []);
    await C65.log('i', 'журнал в storage: ' + log.length + ' записей (окно журнала - внизу вкладки ПОЛУАВТОМАТ; полный отчёт - h6)');
  },

  /* --- ряд F: VPN (факты; управление = скрипт) --- */
  f1: async function () {
    const g = await C65.stGet('geo_direct', null);
    if (!g) { await C65.log('i', 'выходная страна не измерялась (координата: b1)'); return; }
    await C65.log('i', 'выход: ' + g.cc + '/' + g.city + (g.cc === 'RU' ? ' | совпадает с РФ - прокси/VPN не активны на пути' : ' | вне РФ'));
  },
  f2: async function () { await C65.log('i', 'профиль VPN создаёт скрипт, клетка f2 (data\\vpn.json -> Add-VpnConnection): браузер службы RasMan не видит - это факт архитектуры Chrome'); },
  f3: async function () { await C65.log('i', 'подключение VPN = скрипт, клетка f3 (rasdial): из расширения недоступно'); },
  f4: async function () { await C65.log('i', 'отключение VPN = скрипт, клетка f4 (rasdial /disconnect)'); },
  f5: async function () {
    const g = await C65.stGet('geo_direct', null);
    await C65.log('i', 'rasdial вне досягаемости браузера; что видит браузер: выход ' + (g ? g.cc + '/' + g.city : '?') + ' (свежий замер: b1)');
  },
  f6: async function () { await C65.log('i', 'снятие своих профилей CELL65-* = скрипт, клетка f6 (ноль удалений: только свои артефакты)'); },
  f7: async function () {
    await C65.log('i', 'факты: VPN-клиент - часть Windows (RasMan/SstpSvc, rasdial, Параметры -> Сеть -> VPN, есть в Home)');
    await C65.log('i', 'публичные прокси (ряд c) - это НЕ VPN: нет VPN-протокола и учёток');
    await C65.log('i', 'VPN-путь = свой сервер/учётка (скрипт f8 -> f2 -> f3); сторонние клиенты не ставятся');
  },
  f8: async function () {
    const tpl = '{\n  "name": "CELL65-VPN",\n  "server": "vpn.example.com",\n  "user": "login",\n  "pass": "password",\n  "type": "IKEv2",\n  "psk": ""\n}';
    await C65.stSet({ vpn_template: tpl });
    await C65.log('i', 'шаблон vpn.json сохранён в storage (попадает в отчёт h6) - заполни server/user/pass/type (IKEv2|SSTP|L2TP), дальше скрипт f2/f3');
  },

  /* --- ряд G: ПРОКСИ CHROME --- */
  g1: async function () {
    const r = await C65.proxyGet();
    await C65.stSet({ proxy_backup: { ts: new Date().toISOString().slice(0, 19).replace('T', ' '), value: r.ok ? r.value : null, ok: r.ok, err: r.ok ? '' : r.err } });
    if (r.ok) await C65.log('ok', 'бэкап настроек прокси Chrome сохранён: ' + (r.value ? JSON.stringify(r.value).slice(0, 120) : '(не задан)'));
    else await C65.log('!!', 'чтение для бэкапа не удалось (' + r.err + ') - слот бэкапа создан пустым; ОТКАТ g3 уйдёт в direct (факт сохранён)');
  },
  g2: async function () {
    const act = await C65.stGet('active', null);
    const best = await C65.stGet('best', null);
    const servers = await C65.stGet('servers', []);
    if (act) { await C65.applyServerObj(act); return; }
    if (best) { await C65.applyServerObj({ host: best.host, port: best.port, proto: best.proto, ring: best.ring }); return; }
    if (servers.length) { await C65.applyServerObj(servers[0]); return; }
    await C65.log('!!', 'серверов нет - координата: d6 (авто-цикл) или Импорт servers_export.json (СЕРВЕРЫ)');
  },
  g3: async function () {
    const b = await C65.stGet('proxy_backup', null);
    if (b && b.value) { await C65.restoreProxyValue(b.value); await C65.stSet({ active: null }); try { chrome.action.setBadgeText({ text: '' }); } catch (e) {} await C65.log('ok', 'восстановлено из бэкапа (' + b.ts + ')'); return; }
    await C65.setDirect();
    if (b && b.err) await C65.log('ok', 'бэкап пуст по факту ошибки чтения - выставлен direct (откат безопасен, ноль удалений)');
    else await C65.log('ok', 'бэкапа не было - direct выставлен');
  },
  g4: async function () {
    const r = await C65.proxyGet();
    if (!r.ok) { await C65.log('!!', 'настройки прокси не читаются: ' + r.err); return; }
    const v = r.value;
    await C65.log('i', 'настройки: ' + (v ? JSON.stringify(v).slice(0, 200) : '(не заданы - режим system)') + ' | контроль: ' + r.levelOfControl + ' | форма чтения: ' + r.form);
  },
  g5: async function () {
    const g = await C65.fetchGeo(9000);
    if (!g) { await C65.log('!!', 'тест: гео-сервис не ответил (координата: прокси/сеть)'); return; }
    const act = await C65.stGet('active', null);
    await C65.log('i', 'выход сейчас: ' + g.ip + ' (' + g.cc + '/' + g.city + ')' + (act ? ' - через ' + act.host + ':' + act.port : ' - напрямую'));
  },
  g6: async function () { await C65.log('i', 'winhttp-прокси: системный уровень, браузером не читается - координата: скрипт, клетка g6 (netsh winhttp show proxy)'); },
  g7: async function () {
    const bl = await C65.bypassList();
    await C65.log('i', 'bypassList: ' + bl.join(', ') + ' | <local> всегда напрямую (localhost не ходит через прокси)');
  },
  g8: async function () {
    const act = await C65.stGet('active', null);
    const b = await C65.stGet('proxy_backup', null);
    await C65.log('i', 'прокси-отчёт: активный=' + (act ? act.host + ':' + act.port : 'direct') + ' | бэкап=' + (b ? b.ts : 'нет') + ' | полный текст - кнопка ОТЧЁТ (h6) во вкладке АВТОМАТ');
  },

  /* --- ряд H: ЖИЗНЬ --- */
  h1: async function () {
    await C65.flagSet('configured', '1');
    await C65.log('ok', 'порядок настройки (полуавтомат): [c] списки -> [d] проба и выбор -> [g2] включить сервер; затем автомат: h3 + h4');
    await C65.log('i', 'в браузере нет задач планировщика: сторож (h4) держит автоподдержку, пока Chrome запущен');
  },
  h2: async function () {
    await C65.setDirect(true);
    try { await chrome.alarms.clear('cell65_watch'); } catch (e) {}
    await C65.flagSet('watch', '0');
    await C65.stSet({ active: null });
    await C65.log('ok', 'undo: прокси Chrome direct, сторож снят; данные (пул/список/журнал) сохранены - ноль удалений');
  },
  h3: async function () { await C65.runAuto(); },
  h4: async function () { await C65.watchToggle(); },
  h5: async function () {
    const log = await C65.stGet('log', []);
    await C65.log('i', 'журнал: ' + log.length + ' записей в storage (отображается в окне журнала; экспорт - h6)');
  },
  h6: async function () {
    const txt = await C65.reportText();
    await C65.stSet({ report65: txt });
    await C65.log('ok', 'полный отчёт собран (storage: report65; кнопка ОТЧЁТ копирует его в буфер обмена)');
  },
  h7: async function () { await C65.log('i', '\n' + (await C65.boardText())); await C65.log('i', await C65.keyFactsText()); },
  h8: async function () {
    await C65.log('i', 'шпаргалка: c -> d -> g2 (полуавтомат); h3 авто-цикл; h4 сторож; СЕРВЕРЫ - ручной выбор; h2 undo');
    await C65.log('i', 'журнал: storage(log) | отчёт: h6 | vpn: ряд f (управление в скрипте)');
  }
};

/* ---------- автомат ---------- */
C65.runAuto = async function () {
  await C65.scoreDecay(); /* v2.3.0: старение очков за цикл */
  await C65.log('==', 'CELL-65 АВТО-ЦИКЛ старт');
  await C65.runRow('c');
  const pool = await C65.stGet('pool', []);
  if (pool.length) {
    await C65.runRow('d');
    const autoapply = await C65.flagGet('autoapply');
    if (autoapply === '1') {
      await C65.log('--', 'флаг автоприменения: включаю выбранный сервер (g2)');
      await C65.CELLS.g2();
    } else {
      await C65.log('i', 'автоприменение выключено - сервер выбирается вручную (вкладка СЕРВЕРЫ, координата: g2)');
    }
  } else {
    await C65.log('!!', 'пул пуст - ряд d пропущен (координата: ряд c)');
  }
  await C65.log('==', 'CELL-65 АВТО-ЦИКЛ финиш');
};

/* ---------- сторож (зеркало h4 скрипта) ---------- */
C65.watchToggle = async function () {
  const cur = await C65.flagGet('watch');
  if (cur === '1') {
    try { await chrome.alarms.clear('cell65_watch'); } catch (e) {}
    await C65.flagSet('watch', '0');
    await C65.log('ok', 'сторож ВЫКЛ');
  } else {
    try { await chrome.alarms.create('cell65_watch', { periodInMinutes: 30 }); } catch (e) { await C65.log('!!', 'alarms: ' + e.message); return; }
    await C65.flagSet('watch', '1');
    await C65.log('ok', 'сторож ВКЛ: проверка здоровья каждые 30 мин, при сбое - следующий сервер (самолечение)');
  }
};
C65.watchTick = async function () {
  const watch = await C65.flagGet('watch');
  if (watch !== '1') return;
  await C65.log('--', 'сторож: проверка здоровья');
  const act = await C65.stGet('active', null);
  if (!act) { await C65.log('i', 'сторож: прокси не включён - пропуск (включение: g2)'); return; }
  const ms = await C65.time204(8000);
  if (ms >= 0) {
    const real = await C65.realCheck(7000);
    if (real) { await C65.log('ok', 'сторож: здоровье в норме (' + act.host + ':' + act.port + ' -> 204 за ' + ms + ' мс + реальный трафик OK)'); return; }
    await C65.log('!!', 'сторож: 204 есть, реальный трафик нет (' + act.host + ':' + act.port + ') -> смена upstream');
  } else {
    await C65.log('!!', 'сторож: здоровье потеряно (' + act.host + ':' + act.port + ') -> смена upstream');
  }
  const switched = await C65.switchNext();
  if (switched) {
    const ms2 = await C65.time204(8000);
    if (ms2 >= 0) await C65.log('ok', 'сторож: новый сервер отвечает (204 за ' + ms2 + ' мс)');
    else await C65.log('!!', 'сторож: новый тоже не отвечает - координата: авто-цикл (h3)');
  }
};

/* ---------- отчёты ---------- */
C65.keyFactsText = async function () {
  const b = await C65.stGet('best', null);
  const act = await C65.stGet('active', null);
  const pool = await C65.stGet('pool', []);
  const sv = await C65.stGet('servers', []);
  const watch = await C65.flagGet('watch');
  const home = await C65.flagGet('geo_home');
  const lines = [];
  lines.push(' выбор: ' + (b ? ('R' + b.ring + ' ' + b.proto + ' ' + b.host + ':' + b.port + ' | ' + b.cc + '/' + b.city + ' | ' + b.dist_km + ' км | ' + Number(b.http_s).toFixed(2) + ' c') : 'ещё не делался (авто-цикл h3)'));
  lines.push(' активный: ' + (act ? (act.proto + ' ' + act.host + ':' + act.port + (act.ring != null ? (' (R' + act.ring + ')') : '')) : 'direct'));
  lines.push(' пул: ' + pool.length + ' | вне дом-страны в списке: ' + sv.length + ' | сторож: ' + (watch === '1' ? 'ВКЛ' : 'выкл') + ' | дом: ' + (home || '?'));
  if (!act) {
    lines.push(' мост: заблокированные сайты (YouTube, nnm-club) при direct не откроются. Если 65.cmd auto поднял локаль - добавь 127.0.0.1:18080 (HTTP) в СЕРВЕРЫ и примени, либо включи системный прокси (g2/меню [7])');
    lines.push(' подсказка: окно авторизации прокси при direct = системный прокси Windows (Параметры - Сеть и Интернет - Прокси); плагин его не трогает');
  }
  return lines.join('\n');
};
C65.reportText = async function () {
  const out = [];
  out.push('==============================================');
  out.push('CELL-65 :: отчёт плагина ' + new Date().toISOString().slice(0, 19).replace('T', ' '));
  out.push('==============================================');
  out.push('-- доска --');
  out.push(await C65.boardText());
  out.push('-- факты --');
  out.push(await C65.keyFactsText());
  const env = await C65.stGet('env', null);
  if (env) out.push('-- среда --\n' + JSON.stringify(env, null, 1));
  const b = await C65.stGet('best', null);
  if (b) out.push('-- выбор (d6) --\n' + JSON.stringify(b, null, 1));
  const tpl = await C65.stGet('vpn_template', null);
  if (tpl) out.push('-- шаблон vpn.json (заполнить и отдать скрипту, клетки f2/f3) --\n' + tpl);
  const log = await C65.stGet('log', []);
  out.push('-- журнал (хвост 60) --');
  out.push(log.slice(-60).map(function (l) { return l.ts + ' [' + l.tag + '] ' + l.text; }).join('\n'));
  return out.join('\n');
};
