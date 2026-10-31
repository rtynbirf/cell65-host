// «Антицензор MV3» — работа с declarativeNetRequest.
//
// Верифицированные ограничения (официальные доки, см. docs/SOURCES.md):
//   * MAX_NUMBER_OF_DYNAMIC_RULES = 30 000 (Chrome 121+), до этого 5 000;
//   * разрешение "declarativeNetRequest" даёт block/allow/allowAllRequests
//     БЕЗ host-доступа к сайтам; redirect/modifyHeaders требуют
//     "declarativeNetRequestWithHostAccess" — поэтому здесь только block/allow;
//   * requestDomains сопоставляет и поддомены (d = example.com матчит
//     и www.example.com).

// Импортированные из hosts-файлов правила получают id >= BASE.
export const DYNAMIC_IMPORT_BASE_ID = 900000;
// Запас под allow-правила исключений и прочее (лимит 30 000).
const MAX_IMPORT_CHUNKS = 28;
const CHUNK_SIZE = 1000;

const HOSTNAME_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

/** Парсер hosts/adblock-текстов:
 *  поддерживает "0.0.0.0 domain", "127.0.0.1 domain1 domain2",
 *  "||domain^" (adblock), "*.domain", чистые домены.
 *  Комментарии: #, !, //. Строки @@ (adblock-исключения) пропускаются. */
export function parseHosts(text) {
  const out = new Set();
  const lines = String(text || '').split(/\r?\n/);
  for (let raw of lines) {
    let line = raw.trim();
    if (!line) continue;
    const hashIdx = line.indexOf('#');
    if (hashIdx === 0) continue;
    if (hashIdx > 0) line = line.slice(0, hashIdx);
    if (line.startsWith('!') || line.startsWith('//')) continue;
    if (line.startsWith('@@')) continue; // adblock-исключение — не блокируем
    line = line.trim();
    if (!line) continue;
    const tokens = line.split(/\s+/).filter(Boolean);
    for (let tok of tokens) {
      let d = tok.toLowerCase();
      if (d.startsWith('||')) d = d.slice(2);
      if (d.endsWith('^')) d = d.slice(0, -1);
      while (d.startsWith('.')) d = d.slice(1);
      if (d.startsWith('*.')) d = d.slice(2);
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(d)) continue; // IP-литерал слева от домена
      if (d.includes('/') || d.includes(':')) continue; // пути/IPv6 — не домен
      if (!HOSTNAME_RE.test(d)) continue;
      out.add(d);
    }
  }
  return [...out].sort();
}

function chunk(arr, n) {
  const res = [];
  for (let i = 0; i < arr.length; i += n) res.push(arr.slice(i, i + n));
  return res;
}

/** Включение/выключение статических наборов (ads/trackers) по конфигу. */
export async function setStaticToggles(cfg) {
  const enable = [];
  const disable = [];
  (cfg.blockAds ? enable : disable).push('ads');
  (cfg.blockTrackers ? enable : disable).push('trackers');
  const ops = {};
  if (enable.length) ops.enableRulesetIds = enable;
  if (disable.length) ops.disableRulesetIds = disable;
  if (enable.length || disable.length) {
    await chrome.declarativeNetRequest.updateEnabledRulesets(ops);
  }
}

/** Замена всего импортированного набора динамических правил.
 *  Возвращает статистику {parsed, added, chunks, truncated}. */
export async function importHostsText(text, exceptions = []) {
  const parsed = parseHosts(text);
  const exc = exceptions || [];
  const filtered = parsed.filter(
    (d) => !exc.some((e) => d === e || d.endsWith('.' + e))
  );
  let chunks = chunk(filtered, CHUNK_SIZE);
  const truncated = chunks.length > MAX_IMPORT_CHUNKS;
  if (truncated) chunks = chunks.slice(0, MAX_IMPORT_CHUNKS);

  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const toRemove = existing
    .filter((r) => r.id >= DYNAMIC_IMPORT_BASE_ID)
    .map((r) => r.id);

  const addRules = chunks.map((domains, i) => ({
    id: DYNAMIC_IMPORT_BASE_ID + i,
    priority: 1,
    action: { type: 'block' },
    condition: { requestDomains: domains }
  }));

  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: toRemove,
    addRules
  });

  return {
    parsed: parsed.length,
    added: truncated ? filtered.slice(0, MAX_IMPORT_CHUNKS * CHUNK_SIZE).length : filtered.length,
    chunks: addRules.length,
    truncated,
    removedPrev: toRemove.length
  };
}

/** Удаление всех импортированных динамических правил. */
export async function clearImportedRules() {
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  const toRemove = existing
    .filter((r) => r.id >= DYNAMIC_IMPORT_BASE_ID)
    .map((r) => r.id);
  if (toRemove.length) {
    await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: toRemove });
  }
  return toRemove.length;
}

/** Число активных динамических правил импорта. */
export async function importedRulesCount() {
  const existing = await chrome.declarativeNetRequest.getDynamicRules();
  return existing.filter((r) => r.id >= DYNAMIC_IMPORT_BASE_ID).length;
}
