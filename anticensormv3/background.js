// «Антицензор MV3» — service worker (Manifest V3, ES module).
//
// Обязанности:
//   1. Применение прокси-конфигурации через chrome.proxy.settings
//      (режимы: pac / global / direct — см. lib/pac-engine.js).
//   2. Управление статическими наборами DNR (ads/trackers).
//   3. Proxy-аутентификация через webRequest.onAuthRequired
//      (MV3: 'asyncBlocking' + разрешение "webRequestAuthProvider").
//   4. Политика WebRTC (chrome.privacy.webrtc) — против утечки локальных IP.
//   5. Журнал ошибок прокси (chrome.proxy.onProxyError) — кольцевой буфер 50.
//   6. Бейдж-счётчик блокировок (displayActionCountAsBadgeText).

import { DEFAULTS, clone, QUICK_PACS } from './lib/defaults.js';
import { buildProxyConfig } from './lib/pac-engine.js';
import {
  setStaticToggles,
  importHostsText,
  clearImportedRules,
  importedRulesCount
} from './lib/dnr-manager.js';

const ERR_RING_MAX = 50;
let applyTimer = null;

async function getCfg() {
  const st = await chrome.storage.local.get('cfg');
  return Object.assign(clone(DEFAULTS), st.cfg || {});
}

async function getErrlog() {
  const st = await chrome.storage.local.get('errlog');
  return st.errlog || [];
}

/** Полное применение конфигурации. Идемпотентно. */
async function applyAll(reason = 'manual') {
  const cfg = await getCfg();

  // 1. Прокси
  const config = buildProxyConfig(cfg);
  await chrome.proxy.settings.set({ value: config, scope: 'regular' });

  // 2. Статические наборы DNR
  await setStaticToggles(cfg);

  // 3. WebRTC: скрыть локальные IP (default_public_interface_only)
  try {
    if (chrome.privacy && chrome.privacy.webrtc && chrome.privacy.webrtc.webRTCIPHandlingPolicy) {
      await chrome.privacy.webrtc.webRTCIPHandlingPolicy.set({
        value: cfg.webrtcHideIp ? 'default_public_interface_only' : 'default'
      });
    }
  } catch (e) {
    console.warn('WebRTC policy failed:', e);
  }

  // 4. Бейдж: счётчик блокировок или ON/OFF
  const blocking = cfg.blockAds || cfg.blockTrackers;
  try {
    await chrome.declarativeNetRequest.setExtensionActionOptions({
      displayActionCountAsBadgeText: blocking && cfg.badgeCount !== false
    });
  } catch (e) {
    console.warn('badge count failed:', e);
  }
  if (!(blocking && cfg.badgeCount !== false)) {
    const text = cfg.mode === 'direct' ? 'OFF' : 'ON';
    const color = cfg.mode === 'direct' ? '#6b7280' : cfg.mode === 'global' ? '#7c3aed' : '#2563eb';
    await chrome.action.setBadgeText({ text });
    await chrome.action.setBadgeBackgroundColor({ color });
  }
}

function scheduleApply() {
  if (applyTimer) clearTimeout(applyTimer);
  applyTimer = setTimeout(() => {
    applyAll('storage-changed').catch(console.error);
  }, 150);
}

// ---------- События жизненного цикла ----------

chrome.runtime.onInstalled.addListener(async (details) => {
  const st = await chrome.storage.local.get('cfg');
  if (!st.cfg) {
    await chrome.storage.local.set({ cfg: clone(DEFAULTS) });
  }
  if (details.reason === 'install') {
    chrome.tabs.create({ url: chrome.runtime.getURL('options/options.html') });
  }
  await applyAll('installed');
});

chrome.runtime.onStartup.addListener(() => {
  applyAll('startup').catch(console.error);
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.cfg) scheduleApply();
});

// ---------- Proxy-ошибки (журнал) ----------

chrome.proxy.onProxyError.addListener(async (details) => {
  const log = await getErrlog();
  log.unshift({
    t: Date.now(),
    error: details.error,
    fatal: !!details.fatal,
    details: details.details || ''
  });
  await chrome.storage.local.set({ errlog: log.slice(0, ERR_RING_MAX) });
});

// ---------- Proxy-аутентификация (MV3 asyncBlocking) ----------

chrome.webRequest.onAuthRequired.addListener(
  async (details, asyncCallback) => {
    try {
      if (!details.isProxy) {
        asyncCallback({});
        return;
      }
      const cfg = await getCfg();
      if (!cfg.proxyAuthEnabled || !cfg.proxyUser) {
        asyncCallback({});
        return;
      }
      asyncCallback({
        authCredentials: { username: cfg.proxyUser, password: cfg.proxyPass }
      });
    } catch (e) {
      try { asyncCallback({}); } catch (_) { /* окно уже ушло */ }
    }
  },
  { urls: ['<all_urls>'] },
  ['asyncBlocking']
);

// ---------- Сообщения от popup/options/newtab ----------

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  (async () => {
    try {
      const type = msg && msg.type;
      if (type === 'getSummary') {
        const cfg = await getCfg();
        const dynRules = await importedRulesCount();
        sendResponse({
          ok: true,
          cfg,
          errlog: await getErrlog(),
          dynRules
        });
        return;
      }
      if (type === 'applyAll') {
        await applyAll('message');
        sendResponse({ ok: true });
        return;
      }
      if (type === 'importHosts') {
        const cfg = await getCfg();
        const res = await importHostsText(msg.text || '', cfg.exceptions || []);
        sendResponse({ ok: true, res });
        return;
      }
      if (type === 'clearImported') {
        const removed = await clearImportedRules();
        sendResponse({ ok: true, removed });
        return;
      }
      if (type === 'resetAll') {
        await clearImportedRules();
        await chrome.storage.local.set({ cfg: clone(DEFAULTS) });
        await applyAll('reset');
        sendResponse({ ok: true });
        return;
      }
      if (type === 'quickAntizapret') {
        // «Работает сразу»: внешний PAC публичного сервиса «АнтиЗапрет».
        const cfg = await getCfg();
        const next = Object.assign({}, cfg, {
          mode: 'pac',
          pacSource: 'url',
          pacUrl: QUICK_PACS.antizapret.urls[0]
        });
        await chrome.storage.local.set({ cfg: next });
        await applyAll('quick-antizapret');
        sendResponse({ ok: true, pacUrl: next.pacUrl });
        return;
      }
      if (type === 'setNode') {
        // «НАСТРОЙКИ» в попапе: впиши IP узла → «Сохранить и применить».
        const cfg = await getCfg();
        const host = String(msg.host || '').trim();
        if (!host) {
          sendResponse({ ok: false, error: 'empty-host' });
          return;
        }
        const next = Object.assign({}, cfg, {
          proxyHost: host,
          proxyPort: Math.max(1, Math.min(65535, Number(msg.port) || 1080)),
          proxyScheme: ['http', 'https', 'socks5'].includes(msg.scheme) ? msg.scheme : cfg.proxyScheme,
          mode: msg.scope === 'pac' ? 'pac' : 'global',
          pacSource: 'local'
        });
        await chrome.storage.local.set({ cfg: next });
        await applyAll('set-node');
        sendResponse({ ok: true });
        return;
      }
      if (type === 'checkPacUrl') {
        // Проверка доступности PAC-URL (из service worker, есть host_permissions).
        const url = String(msg.url || '');
        if (!/^https?:\/\//i.test(url)) {
          sendResponse({ ok: false, error: 'bad-url' });
          return;
        }
        try {
          const resp = await fetch(url, { cache: 'no-store' });
          const text = await resp.text();
          sendResponse({
            ok: true,
            status: resp.status,
            bytes: text.length,
            hasFindProxy: /FindProxyForURL/.test(text)
          });
        } catch (e) {
          sendResponse({ ok: true, status: 0, error: String(e && e.message || e) });
        }
        return;
      }
      sendResponse({ ok: false, error: 'unknown-type' });
    } catch (e) {
      sendResponse({ ok: false, error: String(e && e.message || e) });
    }
  })();
  return true; // асинхронный sendResponse
});

// Экспорт для тестов (не используется рантаймом SW).
export { applyAll };
