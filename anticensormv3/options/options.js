// «Антицензор MV3» — страница настроек.
// Всё взаимодействие со SW — через chrome.runtime.sendMessage.

const $ = (id) => document.getElementById(id);
const LIST_MODES = ['pac', 'global', 'direct'];

let cfg = null;

function toast(text, isErr = false) {
  const t = $('toast');
  t.textContent = text;
  t.classList.toggle('err', isErr);
  t.hidden = false;
  clearTimeout(toast._t);
  toast._t = setTimeout(() => { t.hidden = true; }, 2200);
}

function send(msg) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(msg, (res) => resolve(res || { ok: false, error: 'no-response' }));
  });
}

function domainsToText(arr) { return (arr || []).join('\n'); }
function textToDomains(text) {
  return String(text || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}

function renderErrlog(log) {
  const ul = $('errlog');
  ul.innerHTML = '';
  $('errCount').textContent = String(log.length);
  if (!log.length) {
    const li = document.createElement('li');
    li.textContent = '— пусто —';
    ul.appendChild(li);
    return;
  }
  for (const e of log.slice(0, 20)) {
    const li = document.createElement('li');
    const d = new Date(e.t).toLocaleString('ru-RU');
    li.textContent = `${d} · fatal=${e.fatal} · ${e.error}`;
    if (e.fatal) li.classList.add('fatal');
    ul.appendChild(li);
  }
}

async function load() {
  const res = await send({ type: 'getSummary' });
  if (!res.ok) { toast('Не удалось загрузить настройки: ' + res.error, true); return; }
  cfg = res.cfg;
  $('version').textContent = `Manifest V3 · Chrome ${/^(\d+)/.exec(navigator.userAgent)?.[1] || '?'}`;

  for (const r of document.querySelectorAll('input[name=mode]')) {
    r.checked = r.value === cfg.mode;
  }
  $('pacScope').value = cfg.pacScope || 'list';
  $('proxyScheme').value = cfg.proxyScheme;
  $('proxyHost').value = cfg.proxyHost;
  $('proxyPort').value = cfg.proxyPort;
  $('proxyAuthEnabled').checked = !!cfg.proxyAuthEnabled;
  $('proxyUser').value = cfg.proxyUser || '';
  $('proxyPass').value = cfg.proxyPass || '';
  $('authRow').style.display = cfg.proxyAuthEnabled ? 'grid' : 'none';
  $('antizensor').value = domainsToText(cfg.antizensor);
  $('exceptions').value = domainsToText(cfg.exceptions);
  $('azCount').textContent = `· ${cfg.antizensor.length}`;
  $('exCount').textContent = `· ${cfg.exceptions.length}`;
  $('blockAds').checked = !!cfg.blockAds;
  $('blockTrackers').checked = !!cfg.blockTrackers;
  $('badgeCount').checked = cfg.badgeCount !== false;
  $('webrtcHideIp').checked = !!cfg.webrtcHideIp;
  $('dynRules').textContent = String(res.dynRules);
  renderErrlog(res.errlog || []);
}

async function collectAndSave() {
  const modeInput = document.querySelector('input[name=mode]:checked');
  const next = {
    mode: modeInput ? modeInput.value : 'pac',
    pacScope: $('pacScope').value,
    proxyScheme: $('proxyScheme').value,
    proxyHost: $('proxyHost').value.trim() || '127.0.0.1',
    proxyPort: Math.max(1, Math.min(65535, Number($('proxyPort').value) || 1080)),
    proxyAuthEnabled: $('proxyAuthEnabled').checked,
    proxyUser: $('proxyUser').value.trim(),
    proxyPass: $('proxyPass').value,
    antizensor: textToDomains($('antizensor').value),
    exceptions: textToDomains($('exceptions').value),
    blockAds: $('blockAds').checked,
    blockTrackers: $('blockTrackers').checked,
    badgeCount: $('badgeCount').checked,
    webrtcHideIp: $('webrtcHideIp').checked
  };
  cfg = Object.assign({}, cfg, next);
  await chrome.storage.local.set({ cfg });
  const res = await send({ type: 'applyAll' });
  $('azCount').textContent = `· ${cfg.antizensor.length}`;
  $('exCount').textContent = `· ${cfg.exceptions.length}`;
  if (res.ok) toast('Сохранено и применено'); else toast('Ошибка применения: ' + res.error, true);
}

function bindAutoSave() {
  const debounced = (() => {
    let t; return () => { clearTimeout(t); t = setTimeout(collectAndSave, 600); };
  })();
  for (const sel of ['proxyScheme', 'pacScope']) {
    $(sel).addEventListener('change', collectAndSave);
  }
  for (const sel of ['proxyHost', 'proxyPort', 'proxyUser', 'proxyPass', 'antizensor', 'exceptions']) {
    $(sel).addEventListener('input', debounced);
  }
  for (const sel of ['proxyAuthEnabled', 'blockAds', 'blockTrackers', 'badgeCount', 'webrtcHideIp']) {
    $(sel).addEventListener('change', () => {
      $('authRow').style.display = $('proxyAuthEnabled').checked ? 'grid' : 'none';
      collectAndSave();
    });
  }
  for (const r of document.querySelectorAll('input[name=mode]')) {
    r.addEventListener('change', collectAndSave);
  }
}

function bindActions() {
  $('btnApply').addEventListener('click', collectAndSave);

  $('btnOpenDoh').addEventListener('click', () => {
    chrome.tabs.create({ url: 'chrome://settings/security' });
  });

  $('btnPickHosts').addEventListener('click', () => $('fileHosts').click());
  $('fileHosts').addEventListener('change', async (ev) => {
    const f = ev.target.files[0];
    if (!f) return;
    const text = await f.text();
    $('hostsText').value = text;
  });

  $('btnImportHosts').addEventListener('click', async () => {
    const text = $('hostsText').value;
    if (!text.trim()) { toast('Пусто — импортировать нечего', true); return; }
    const res = await send({ type: 'importHosts', text });
    if (res.ok) {
      const r = res.res;
      $('importInfo').textContent =
        `распознано ${r.parsed}, заблокировано ${r.added}, правил ${r.chunks}` +
        (r.truncated ? ' (ОБРЕЗАНО по лимиту DNR)' : '');
      toast('Импорт применён');
      load();
    } else {
      toast('Ошибка импорта: ' + res.error, true);
    }
  });

  $('btnClearImport').addEventListener('click', async () => {
    const res = await send({ type: 'clearImported' });
    if (res.ok) {
      $('importInfo').textContent = `удалено правил: ${res.removed}`;
      $('dynRules').textContent = '0';
      toast('Импортированные правила удалены');
    }
  });

  $('btnExport').addEventListener('click', () => {
    const blob = new Blob([JSON.stringify(cfg, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'anticensormv3-settings.json';
    a.click();
    URL.revokeObjectURL(a.href);
  });

  $('btnImport').addEventListener('click', () => $('fileSettings').click());
  $('fileSettings').addEventListener('change', async (ev) => {
    const f = ev.target.files[0];
    if (!f) return;
    try {
      const obj = JSON.parse(await f.text());
      cfg = obj;
      await chrome.storage.local.set({ cfg });
      await send({ type: 'applyAll' });
      load();
      toast('Настройки импортированы');
    } catch (e) {
      toast('Некорректный JSON: ' + e.message, true);
    }
  });

  $('btnReset').addEventListener('click', async () => {
    if (!confirm('Сбросить все настройки и удалить импортированные правила?')) return;
    const res = await send({ type: 'resetAll' });
    if (res.ok) { toast('Сброшено'); load(); }
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  await load();
  bindAutoSave();
  bindActions();
});
