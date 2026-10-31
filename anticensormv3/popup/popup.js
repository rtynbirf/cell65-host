// «Антицензор MV3» — попап: статус + быстрое переключение режимов.

const $ = (id) => document.getElementById(id);

function send(msg) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(msg, (res) => resolve(res || { ok: false, error: 'no-response' }));
  });
}

function modeLabel(mode) {
  return mode === 'global' ? 'Всё через прокси' : mode === 'direct' ? 'Напрямую' : 'PAC';
}

function render(res) {
  if (!res.ok) {
    $('state').textContent = 'ОШИБКА';
    $('state').className = 'state err';
    return;
  }
  const cfg = res.cfg;
  for (const btn of document.querySelectorAll('.modes button')) {
    btn.classList.toggle('active', btn.dataset.mode === cfg.mode);
  }
  const on = cfg.mode !== 'direct';
  $('state').textContent = on ? (cfg.mode === 'global' ? 'GLOBAL' : 'PAC · ON') : 'OFF';
  $('state').className = 'state ' + (on ? 'on' : 'off');
  $('proxy').textContent = cfg.mode === 'direct'
    ? '—'
    : `${cfg.proxyScheme}://${cfg.proxyHost}:${cfg.proxyPort}`;
  const b = [];
  if (cfg.blockAds) b.push('реклама');
  if (cfg.blockTrackers) b.push('трекеры');
  $('blocking').textContent = b.length ? b.join(' + ') : 'выключена';
  $('dyn').textContent = String(res.dynRules);
  const lastErr = (res.errlog || [])[0];
  $('lastErrRow').hidden = !lastErr;
  if (lastErr) $('lastErr').textContent = lastErr.error.slice(0, 60);
  $('blockAds').checked = !!cfg.blockAds;
  $('blockTrackers').checked = !!cfg.blockTrackers;
  $('webrtcHideIp').checked = !!cfg.webrtcHideIp;
}

async function load() { render(await send({ type: 'getSummary' })); }

async function setMode(mode) {
  const res = await send({ type: 'getSummary' });
  if (!res.ok) return;
  const cfg = Object.assign({}, res.cfg, { mode });
  await chrome.storage.local.set({ cfg });
  load();
}

async function toggleSetting(key, checked) {
  const res = await send({ type: 'getSummary' });
  if (!res.ok) return;
  const cfg = Object.assign({}, res.cfg);
  cfg[key] = checked;
  await chrome.storage.local.set({ cfg });
  load();
}

document.addEventListener('DOMContentLoaded', () => {
  load();
  for (const btn of document.querySelectorAll('.modes button')) {
    btn.addEventListener('click', () => setMode(btn.dataset.mode));
  }
  $('blockAds').addEventListener('change', (e) => toggleSetting('blockAds', e.target.checked));
  $('blockTrackers').addEventListener('change', (e) => toggleSetting('blockTrackers', e.target.checked));
  $('webrtcHideIp').addEventListener('change', (e) => toggleSetting('webrtcHideIp', e.target.checked));
  $('btnOptions').addEventListener('click', () => chrome.runtime.openOptionsPage());
});
