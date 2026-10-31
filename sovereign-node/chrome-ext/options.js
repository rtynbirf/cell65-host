// options.js — форма режимов, валидация, сохранение в chrome.storage.sync.
'use strict';

const $ = (id) => document.getElementById(id);
const PUBLIC_URL = 'https://p.thenewone.lol:8443/proxy.pac';

function currentMode() {
  const checked = document.querySelector('input[name="mode"]:checked');
  return checked ? checked.value : 'node';
}

function syncUi() {
  const mode = currentMode();
  $('nodeFields').style.display = mode === 'node' ? 'flex' : 'none';
  $('pacLine').style.display = mode === 'node' ? 'block' : 'none';
  updatePacLine();
}

function validHostPort() {
  const host = $('host').value.trim();
  const port = $('port').value.trim() || '3128';
  if (!/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(host)) return null;
  if (!/^\d{1,5}$/.test(port) || +port < 1 || +port > 65535) return null;
  return { host, port: +port };
}

function updatePacLine() {
  const hp = validHostPort();
  $('pacLine').textContent = hp
    ? `var PAC_PROXY = 'PROXY ${hp.host}:${hp.port}; DIRECT';`
    : `var PAC_PROXY = 'PROXY АДРЕС_УЗЛА:3128; DIRECT';  // впиши IP:порт слева`;
}

document.querySelectorAll('input[name="mode"]').forEach((el) => {
  el.addEventListener('change', syncUi);
});
$('host').addEventListener('input', updatePacLine);
$('port').addEventListener('input', updatePacLine);

function flashStatus() {
  const s = $('status');
  s.classList.add('show');
  setTimeout(() => s.classList.remove('show'), 2200);
}

$('save').addEventListener('click', async () => {
  const mode = currentMode();
  if (mode === 'node') {
    const hp = validHostPort();
    if (!hp) {
      alert('Адрес узла: только буквы/цифры/точки/дефисы, порт 1–65535.\nПример: 203.0.113.7, порт 3128.');
      return;
    }
    await chrome.storage.sync.set({ mode, host: hp.host, port: hp.port });
  } else {
    await chrome.storage.sync.set({ mode });
  }
  await chrome.runtime.sendMessage({ type: 'apply' });
  flashStatus();
});

// Загрузка текущего конфига
(async () => {
  const cfg = await chrome.storage.sync.get({ mode: 'node', host: '', port: 3128 });
  document.querySelector(`input[name="mode"][value="${cfg.mode}"]`).checked = true;
  $('host').value = cfg.host || '';
  $('port').value = cfg.port || 3128;
  syncUi();
})();
