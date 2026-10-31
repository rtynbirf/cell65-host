// popup.js — статус, тумблер, пресет, переход в настройки.
'use strict';

const $ = (id) => document.getElementById(id);
const MODE_NAMES = {
  node: 'Свой узел (PAC «Антицензор» встроен)',
  public: 'Публичный PAC «АнтиЗапрет»',
  off: 'Выключено',
};
const PUBLIC_URL = 'https://p.thenewone.lol:8443/proxy.pac';

function render(st) {
  const cfg = st.cfg || {};
  const dot = $('dot');
  const state = $('state');
  const active = st.active && cfg.mode !== 'off' && !(cfg.mode === 'node' && !(cfg.host || '').trim());

  dot.className = 'dot ' + (active ? 'on' : (cfg.mode === 'node' && !(cfg.host || '').trim() ? 'warn' : 'off'));
  state.textContent = active ? 'РАБОТАЕТ' : (cfg.mode === 'node' && !(cfg.host || '').trim() ? 'ЖДЁТ АДРЕСА УЗЛА' : 'ВЫКЛЮЧЕНО');

  $('modeName').textContent = MODE_NAMES[cfg.mode] || '—';
  if (cfg.mode === 'node') {
    $('modeAddr').textContent = cfg.host ? `${cfg.host}:${cfg.port || 3128}` : 'адрес узла не вписан';
    $('modeHint').innerHTML = cfg.host
      ? 'Заблокированные домены идут через твой узел, всё остальное — напрямую. Браузер спросит логин/пароль при первом заходе (407).'
      : '<b>ШАГ 1:</b> нажми «НАСТРОЙКИ» и впиши адрес узла (IP:3128 от enable-pac-endpoint.sh).';
    $('presetRow').style.display = 'flex';
  } else if (cfg.mode === 'public') {
    $('modeAddr').textContent = PUBLIC_URL;
    $('modeHint').textContent = 'Работает сразу, но трафик заблокированных сайтов идёт через чужой сервис. Суверенный вариант — «свой узел» в настройках.';
    $('presetRow').style.display = 'none';
  } else {
    $('modeAddr').textContent = '';
    $('modeHint').textContent = 'Прокси не задан — браузер ходит напрямую.';
    $('presetRow').style.display = 'none';
  }

  const t = $('toggle');
  t.textContent = cfg.mode === 'off' ? 'ВКЛЮЧИТЬ' : 'ВЫКЛЮЧИТЬ';
  t.classList.toggle('primary', cfg.mode === 'off');
}

async function refresh() {
  const resp = await chrome.runtime.sendMessage({ type: 'status' });
  if (resp && resp.ok) render(resp);
}

$('toggle').addEventListener('click', async () => {
  await chrome.runtime.sendMessage({ type: 'toggle' });
  refresh();
});
$('settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('preset').addEventListener('click', async () => {
  await chrome.storage.sync.set({ mode: 'public' });
  refresh();
});
$('pacCheck').addEventListener('click', async (e) => {
  e.preventDefault();
  const cfg = (await chrome.runtime.sendMessage({ type: 'status' })).cfg;
  const url = cfg.mode === 'node'
    ? chrome.runtime.getURL('pac/anticensor.pac')
    : PUBLIC_URL;
  window.open(url, '_blank');
});

refresh();
