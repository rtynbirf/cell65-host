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
  const azMode = on && cfg.mode === 'pac' && cfg.pacSource === 'url' && cfg.pacUrl;
  $('state').textContent = on ? (cfg.mode === 'global' ? 'GLOBAL' : azMode ? 'PAC · AZ' : 'PAC · ON') : 'OFF';
  $('state').className = 'state ' + (on ? 'on' : 'off');
  let proxyText;
  if (cfg.mode === 'direct') proxyText = '—';
  else if (azMode) { try { proxyText = 'PAC: ' + new URL(cfg.pacUrl).host; } catch (_) { proxyText = 'PAC (URL)'; } }
  else proxyText = `${cfg.proxyScheme}://${cfg.proxyHost}:${cfg.proxyPort}`;
  $('proxy').textContent = proxyText;
  $('pacSrc').textContent = cfg.mode !== 'pac'
    ? '— (режим ' + (cfg.mode === 'global' ? 'весь трафик' : 'напрямую') + ')'
    : azMode ? 'внешний PAC-файл (URL)' : 'свой список (' + (cfg.antizensor || []).length + ')';
  $('nodeHost').value = cfg.proxyHost || '';
  $('nodePort').value = cfg.proxyPort || 1080;
  $('nodeScheme').value = cfg.proxyScheme || 'socks5';
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
  // Кнопка «PAC · список» возвращает к собственному списку расширения
  if (mode === 'pac' && cfg.pacSource === 'url') cfg.pacSource = 'local';
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

function setQ(elId, text, okClass) {
  const el = $(elId);
  el.textContent = text;
  el.className = 'qres' + (okClass === true ? ' ok' : okClass === false ? ' err' : '');
}

async function quickAntizapret() {
  const res = await send({ type: 'quickAntizapret' });
  setQ('quickResult', res.ok ? '✓ включён PAC «АнтиЗапрет»' : 'ошибка: ' + (res.error || 'нет ответа'), res.ok);
  load();
}

async function checkQuick() {
  const res = await send({ type: 'getSummary' });
  if (!res.ok) return;
  const url = res.cfg.pacUrl;
  if (!url) { setQ('quickResult', 'PAC-URL не задан', false); return; }
  setQ('quickResult', 'проверяю…');
  const chk = await send({ type: 'checkPacUrl', url });
  if (!chk.ok) { setQ('quickResult', 'сеть недоступна', false); return; }
  if (chk.status === 200 && chk.hasFindProxy) {
    setQ('quickResult', `✓ PAC доступен (${chk.bytes} байт) — работаем`, true);
  } else if (chk.status === 403) {
    setQ('quickResult', '403: сервис пускает только RU-гео → впишите свой узел в «НАСТРОЙКАХ»', false);
  } else if (chk.error) {
    setQ('quickResult', `HTTP ${chk.status} · ${chk.error}`, false);
  } else {
    setQ('quickResult', `HTTP ${chk.status}` + (chk.hasFindProxy ? ' · PAC есть' : ' · это не PAC-файл'), false);
  }
}

async function saveNode() {
  const scopeInput = document.querySelector('input[name=nodeScope]:checked');
  const res = await send({
    type: 'setNode',
    host: $('nodeHost').value,
    port: $('nodePort').value,
    scheme: $('nodeScheme').value,
    scope: scopeInput ? scopeInput.value : 'global'
  });
  if (res.ok) setQ('nodeResult', '✓ сохранено и применено', true);
  else setQ('nodeResult', res.error === 'empty-host' ? 'введите IP/хост узла' : 'ошибка: ' + (res.error || ''), false);
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
  $('btnQuick').addEventListener('click', quickAntizapret);
  $('btnQuickCheck').addEventListener('click', checkQuick);
  $('btnNodeToggle').addEventListener('click', () => {
    const b = $('nodeBody');
    b.hidden = !b.hidden;
    $('btnNodeToggle').textContent = b.hidden ? 'НАСТРОЙКИ узла ▾' : 'НАСТРОЙКИ узла ▴';
  });
  $('btnNodeSave').addEventListener('click', saveNode);
});
