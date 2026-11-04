// Антицензор — СУВЕРЕННЫЙ УЗЕЛ (rtynbirf/cell65-host)
// Service worker: применяет PAC по конфигу из chrome.storage.sync.
// MV3-совместимо: никакого eval, никакого удалённого кода — PAC либо встроен,
// либо передаётся сетевому стеку Chrome как url (как системный PAC).
'use strict';

const BUNDLED_PAC_URL = chrome.runtime.getURL('pac/anticensor.pac');
const PUBLIC_PAC_URL = 'https://p.thenewone.lol:8443/proxy.pac'; // «АнтиЗапрет», гео: РФ
const DEFAULT_CONFIG = { mode: 'node', host: '', port: 3128 };

async function getConfig() {
  return chrome.storage.sync.get(DEFAULT_CONFIG);
}

function buildProxyLine(cfg) {
  const port = parseInt(cfg.port, 10) || 3128;
  return `PROXY ${cfg.host}:${port}; DIRECT`;
}

// Встроенный PAC: заменяем ЕДИНСТВЕННУЮ строку конфига — строку прокси.
function patchPac(pacText, proxyLine) {
  return pacText.replace(/var PAC_PROXY = '[^']*';/, `var PAC_PROXY = '${proxyLine}';`);
}

async function buildPacData(cfg) {
  const resp = await fetch(BUNDLED_PAC_URL);
  const pacText = await resp.text();
  return patchPac(pacText, buildProxyLine(cfg));
}

async function setBadge(text, color) {
  await chrome.action.setBadgeText({ text });
  await chrome.action.setBadgeBackgroundColor({ color });
}

async function clearProxy() {
  await chrome.proxy.settings.clear({ scope: 'regular' });
  await setBadge('OFF', '#5A6470');
}

async function apply() {
  try {
    const cfg = await getConfig();
    if (cfg.mode === 'off') {
      await clearProxy();
      return;
    }
    if (cfg.mode === 'public') {
      await chrome.proxy.settings.set({
        value: { mode: 'pac_script', pacScript: { url: PUBLIC_PAC_URL } },
        scope: 'regular',
      });
      await setBadge('ON', '#1F7A33');
      return;
    }
    // mode === 'node' — свой узел
    const host = String(cfg.host || '').trim();
    if (!host) {
      // Хост ещё не вписан — нейтральное состояние: ничего не перенаправляем.
      await clearProxy();
      await setBadge('?', '#B58A00');
      return;
    }
    const data = await buildPacData(cfg);
    await chrome.proxy.settings.set({
      value: { mode: 'pac_script', pacScript: { data } },
      scope: 'regular',
    });
    await setBadge('ON', '#1F7A33');
  } catch (e) {
    await setBadge('!', '#A02020');
  }
}

chrome.runtime.onInstalled.addListener(() => apply());
chrome.runtime.onStartup.addListener(() => apply());
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync') apply();
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    try {
      if (msg && msg.type === 'status') {
        const cfg = await getConfig();
        const cur = await chrome.proxy.settings.get({ scope: 'regular' });
        sendResponse({ ok: true, cfg, active: !!(cur && cur.value) });
      } else if (msg && msg.type === 'apply') {
        await apply();
        sendResponse({ ok: true });
      } else if (msg && msg.type === 'toggle') {
        const cfg = await getConfig();
        if (cfg.mode === 'off') {
          await chrome.storage.sync.set({ mode: cfg.host ? 'node' : 'public' });
        } else {
          await chrome.storage.sync.set({ mode: 'off' });
        }
        sendResponse({ ok: true });
      } else {
        sendResponse({ ok: false, error: 'unknown message' });
      }
    } catch (e) {
      sendResponse({ ok: false, error: String(e) });
    }
  })();
  return true; // асинхронный sendResponse
});
