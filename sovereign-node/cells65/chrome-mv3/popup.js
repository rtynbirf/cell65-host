'use strict';
/* CELL-65 :: popup.js - три режима:
 * ПОЛУАВТОМАТ: доска 8x8 (клик = клетка a1..h8) + ряды a..h + журнал;
 * АВТОМАТ: авто-цикл (c->d->g2*) + сторож + отчёт/undo;
 * СЕРВЕРЫ: ручное переключение (клик = включить), приоритет кольцо СПБ -> скорость.
 * Команды уходят сервис-воркеру: тяжёлая работа живёт даже при закрытом попапе. */

function $(id) { return document.getElementById(id); }
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
}

let CUR_TAB = 'semi';
let BUSY = false;

async function send(cmd, extra) {
  const msg = Object.assign({ cmd: cmd }, extra || {});
  try { return await chrome.runtime.sendMessage(msg); }
  catch (e) { return { ok: false, err: String(e && e.message || e) }; }
}

/* ---------- рендер ---------- */
async function renderStatus() {
  const o = await chrome.storage.local.get(['active', 'busy', 'busy_label']);
  const st = $('status');
  if (o.busy) {
    st.textContent = 'идёт: ' + (o.busy_label || 'работа') + ' - кнопки заблокированы';
    st.className = 'status busy';
  } else if (o.active) {
    st.textContent = 'включён: ' + o.active.host + ':' + o.active.port + ' (' + o.active.proto + ', R' + o.active.ring + ') - только Chrome';
    st.className = 'status on';
  } else {
    st.textContent = 'прокси выключен (DIRECT)';
    st.className = 'status off';
  }
}

async function renderBoard() {
  const board = (await chrome.storage.local.get(['board'])).board || {};
  const host = $('board');
  const frag = document.createDocumentFragment();
  const rows = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
  for (const r of rows) {
    const lbl = document.createElement('span');
    lbl.className = 'rowlbl'; lbl.textContent = r;
    frag.appendChild(lbl);
    for (let c = 1; c <= 8; c++) {
      const id = r + c;
      const stt = board[id] || '.';
      const d = document.createElement('div');
      d.className = 'cell' + (stt === 'o' ? ' ok' : stt === 'x' ? ' fail' : stt === '>' ? ' run' : '');
      d.textContent = stt;
      d.dataset.id = id;
      d.title = id + ' :: ' + (C65.META[id] || '');
      frag.appendChild(d);
    }
  }
  host.textContent = '';
  host.appendChild(frag);
}

async function renderLogs() {
  const log = (await chrome.storage.local.get(['log'])).log || [];
  const tail = log.slice(-30);
  for (const hostId of ['log', 'log2']) {
    const host = $(hostId);
    if (!host) continue;
    host.innerHTML = tail.map(function (l) {
      const cls = l.tag === 'ok' ? 'l-ok' : (l.tag === '!!' ? 'l-err' : (l.tag === '--' || l.tag === '==' ? 'l-warn' : 'l-dim'));
      return '<div class="' + cls + '">' + esc(l.ts) + ' [' + esc(l.tag) + '] ' + esc(l.text) + '</div>';
    }).join('');
    host.scrollTop = host.scrollHeight;
  }
}

async function renderAuto() {
  const f = (await chrome.storage.local.get(['flags'])).flags || {};
  $('chkApply').checked = f.autoapply === '1';
  $('btnWatch').textContent = f.watch === '1' ? 'СТОРОЖ: ВКЛ (нажми, чтобы выключить)' : 'СТОРОЖ: ВЫКЛ (нажми, чтобы включить)';
}

async function renderSrv() {
  const o = await chrome.storage.local.get(['servers', 'best', 'ts_best', 'ts_pool', 'active']);
  const meta = $('srvmeta');
  const b = o.best;
  meta.textContent = 'выбор: ' + (b
    ? ('R' + b.ring + ' ' + b.cc + '/' + b.city + ' | ' + b.dist_km + ' км | ' + Number(b.http_s).toFixed(2) + ' c | ' + (o.ts_best || ''))
    : 'ещё не делался (АВТО-ЦИКЛ)') +
    ' | пул: ' + ((await chrome.storage.local.get(['pool'])).pool || []).length +
    ' | вне дом-страны: ' + (o.servers || []).length;
  const list = $('srvlist');
  list.textContent = '';
  if (!(o.servers || []).length) {
    const e = document.createElement('div');
    e.className = 'empty';
    e.textContent = 'список пуст: запусти АВТО-ЦИКЛ во вкладке АВТОМАТ - или Импорт (data\\servers_export.json из скрипта).';
    list.appendChild(e);
    return;
  }
  (o.servers || []).forEach(function (s, i) {
    const isActive = o.active && String(o.active.host) === String(s.host) && parseInt(o.active.port, 10) === parseInt(s.port, 10);
    const div = document.createElement('div');
    div.className = 'item' + (isActive ? ' active' : '');
    const rk = document.createElement('span'); rk.className = 'rk'; rk.textContent = '#' + (i + 1);
    const ring = document.createElement('span');
    const rr = parseInt(s.ring, 10);
    ring.className = 'ring' + (rr === 5 ? ' r5' : (rr === 9 || !rr ? ' r9' : ''));
    ring.textContent = rr && rr !== 9 ? 'R' + rr : 'R?';
    const main = document.createElement('div'); main.className = 'main';
    const host = document.createElement('div'); host.className = 'host'; host.textContent = s.host + ':' + s.port;
    const meta2 = document.createElement('div'); meta2.className = 'meta';
    const geo = [s.city, s.cc].filter(Boolean).join(', ');
    const km = (s.dist_km != null && s.dist_km >= 0) ? Math.round(s.dist_km) + ' км' : '';
    const sec = s.http_s ? ' · ' + Number(s.http_s).toFixed(2) + ' c' : '';
    const sc = (typeof s.score === 'number') ? ' · sc' + Math.round(s.score) : '';
    meta2.textContent = [geo, km].filter(Boolean).join(' · ') + sec + sc;
    const pr = document.createElement('span'); pr.className = 'proto'; pr.textContent = String(s.proto || 'http').toUpperCase();
    main.appendChild(host); main.appendChild(meta2);
    div.appendChild(rk); div.appendChild(ring); div.appendChild(main); div.appendChild(pr);
    div.addEventListener('click', async function () {
      if (BUSY) return;
      await send('srv', { srv: s });
      renderAll();
    });
    list.appendChild(div);
  });
}

async function setButtonsDisabled(v) {
  document.querySelectorAll('button, input[type=checkbox]').forEach(function (x) { x.disabled = v; });
}

async function renderAll() {
  await renderStatus();
  await renderBoard();
  await renderLogs();
  await renderAuto();
  await renderSrv();
  BUSY = await C65.busyGet();
  setButtonsDisabled(BUSY);
}

/* ---------- запуск ---------- */
async function boot() {
  /* ряды a..h */
  const grid = $('rowsGrid');
  grid.textContent = '';
  for (const r of Object.keys(C65.ROWS)) {
    const b = document.createElement('button');
    b.className = 'rbtn';
    b.innerHTML = '<b>' + r + '</b>' + C65.ROWS[r];
    b.title = 'запустить весь ряд ' + r + ' (клетки ' + r + '1..' + r + '8)';
    b.addEventListener('click', async function () {
      if (BUSY) return;
      await send('row', { row: r });
    });
    grid.appendChild(b);
  }

  /* доска: клик = клетка */
  $('board').addEventListener('click', async function (ev) {
    const id = ev.target && ev.target.dataset ? ev.target.dataset.id : null;
    if (!id || BUSY) return;
    await send('cell', { id: id });
  });

  /* вкладки */
  document.querySelectorAll('.tab').forEach(function (t) {
    t.addEventListener('click', function () {
      CUR_TAB = t.dataset.tab;
      document.querySelectorAll('.tab').forEach(function (x) { x.classList.toggle('active', x === t); });
      document.querySelectorAll('.pane').forEach(function (p) { p.hidden = (p.id !== 'tab-' + CUR_TAB); });
    });
  });

  /* автомат */
  $('btnAutoCycle').addEventListener('click', async function () { if (!BUSY) await send('auto'); });
  $('chkApply').addEventListener('change', async function (ev) {
    await C65.flagSet('autoapply', ev.target.checked ? '1' : '0');
    await C65.log('i', 'флаг автоприменения: ' + (ev.target.checked ? 'ВКЛ (авто-цикл сам включит выбранный сервер, g2)' : 'ВЫКЛ'));
  });
  $('btnWatch').addEventListener('click', async function () { if (!BUSY) await send('watch'); });
  $('btnReport').addEventListener('click', async function () {
    await send('report');
    const txt = (await chrome.storage.local.get(['report65'])).report65 || '';
    try {
      await navigator.clipboard.writeText(txt);
      await C65.log('ok', 'отчёт скопирован в буфер обмена (' + txt.length + ' символов)');
    } catch (e) {
      await C65.log('i', 'буфер закрыт браузером - отчёт лежит в storage(report65), виден в журнале');
    }
    renderAll();
  });
  $('btnUndo').addEventListener('click', async function () {
    if (BUSY) return;
    if (!confirm('UNDO (h2): прокси Chrome -> direct, сторож выключить. Данные (пул/список/журнал) не трогаются. Продолжить?')) return;
    await send('undo');
    renderAll();
  });

  /* серверы */
  $('btnDirect').addEventListener('click', async function () { await send('direct'); renderAll(); });
  $('btnOpts').addEventListener('click', function () { chrome.runtime.openOptionsPage(); });

  await renderAll();
  setInterval(renderAll, 900);
}

document.addEventListener('DOMContentLoaded', boot);
