'use strict';
/* CELL-65 Switch :: options - импорт data\servers_export.json в chrome.storage.local */

function el(id) { return document.getElementById(id); }
function msg(text, ok) {
  const m = el('msg');
  m.textContent = text;
  m.className = ok ? 'ok' : 'err';
}

function normalizeList(j) {
  let arr = null;
  if (Array.isArray(j)) arr = j;
  else if (j && Array.isArray(j.servers)) arr = j.servers;
  if (!arr) throw new Error('в JSON нет массива servers');
  const clean = [];
  for (const s of arr) {
    const hm = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(String((s && s.host) || '').trim());
    if (!hm || +hm[1] > 255 || +hm[2] > 255 || +hm[3] > 255 || +hm[4] > 255) continue;
    if (!s || !s.port) continue;
    const port = parseInt(s.port, 10);
    if (!port || port < 1 || port > 65535) continue;
    clean.push({
      host: String(s.host),
      port: port,
      proto: String(s.proto || 'http').toLowerCase(),
      country: s.country || '',
      cc: s.cc || '',
      city: s.city || '',
      dist_km: (typeof s.dist_km === 'number') ? s.dist_km : (parseFloat(s.dist_km) || -1),
      ring: (typeof s.ring === 'number') ? s.ring : (parseInt(s.ring, 10) || 9),
      score: (typeof s.score === 'number') ? s.score : 50,
      http_s: String(s.http_s || '')
    });
  }
  if (!clean.length) throw new Error('в JSON нет ни одной валидной записи host:port');
  return clean;
}

async function importJsonText(text) {
  try {
    const j = JSON.parse(text);
    const clean = normalizeList(j);
    await chrome.storage.local.set({ servers: clean, imported_ts: String(j.ts || '') });
    msg('OK: загружено серверов - ' + clean.length + (j.ts ? (' (' + j.ts + ')') : ''), true);
    showCur();
  } catch (e) {
    msg('сбой: ' + (e && e.message ? e.message : e), false);
  }
}

async function showCur() {
  const o = await chrome.storage.local.get(['servers', 'imported_ts', 'active']);
  const n = Array.isArray(o.servers) ? o.servers.length : 0;
  el('cur').textContent = 'в хранилище: ' + n + ' серверов' +
    (o.imported_ts ? (' · импорт: ' + o.imported_ts) : '') +
    (o.active ? (' · включён: ' + o.active.host + ':' + o.active.port) : ' · прокси выключен');
}

el('btnPaste').addEventListener('click', function () { importJsonText(el('txt').value); });

el('btnFile').addEventListener('click', function () {
  const f = el('file').files && el('file').files[0];
  if (!f) { msg('файл не выбран (кнопка слева выбирает, потом "Импорт из файла")', false); return; }
  const r = new FileReader();
  r.onload = function () { importJsonText(String(r.result)); };
  r.onerror = function () { msg('файл не прочитался', false); };
  r.readAsText(f, 'utf-8');
});

el('btnClear').addEventListener('click', async function () {
  await chrome.storage.local.set({ servers: [], imported_ts: '' });
  msg('список очищен (прокси Chrome не менялся)', true);
  showCur();
});

el('btnDirect').addEventListener('click', async function () {
  await chrome.proxy.settings.set({ value: { mode: 'direct' }, scope: 'regular' });
  await chrome.storage.local.set({ active: null });
  chrome.action.setBadgeText({ text: '' });
  msg('прокси Chrome выключен (DIRECT)', true);
  showCur();
});

document.addEventListener('DOMContentLoaded', showCur);
