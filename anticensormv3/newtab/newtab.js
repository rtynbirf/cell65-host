// «Антицензор MV3» — новая вкладка: часы, поиск, плитки ссылок.
// Никакой телеметрии и сетевых запросов, кроме явного поиска/перехода.

const $ = (id) => document.getElementById(id);

const ENGINES = {
  ddg: 'https://duckduckgo.com/?q=',
  google: 'https://www.google.com/search?q=',
  yandex: 'https://yandex.ru/search/?text=',
  bing: 'https://www.bing.com/search?q='
};

const NEWTAB_DEFAULTS = {
  engine: 'ddg',
  links: [
    { t: 'GitHub', u: 'https://github.com' },
    { t: 'YouTube', u: 'https://www.youtube.com' },
    { t: 'Wikipedia', u: 'https://ru.wikipedia.org' },
    { t: 'Telegram', u: 'https://web.telegram.org' },
    { t: 'Proton Mail', u: 'https://mail.proton.me' },
    { t: 'Reddit', u: 'https://www.reddit.com' }
  ]
};

async function loadState() {
  const st = await chrome.storage.local.get('newtab');
  return Object.assign(JSON.parse(JSON.stringify(NEWTAB_DEFAULTS)), st.newtab || {});
}
async function saveState(state) {
  await chrome.storage.local.set({ newtab: state });
}

function normalizeUrl(u) {
  let s = String(u || '').trim();
  if (!s) return '';
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) s = 'https://' + s;
  return s;
}

function faviconFor(urlStr) {
  // Плитка-заглушка: цветной градиент, без внешних запросов (приватность).
  return '<span class="fav"></span>';
}

function renderLinks(state) {
  const wrap = $('links');
  wrap.innerHTML = '';
  state.links.forEach((link, idx) => {
    const a = document.createElement('a');
    a.className = 'tile';
    a.href = normalizeUrl(link.u);
    a.innerHTML = faviconFor(link.u) + `<span>${(link.t || link.u).slice(0, 14)}</span>`;
    const rm = document.createElement('button');
    rm.className = 'rm';
    rm.textContent = '×';
    rm.title = 'Удалить';
    rm.addEventListener('click', async (e) => {
      e.preventDefault();
      e.stopPropagation();
      state.links.splice(idx, 1);
      await saveState(state);
      renderLinks(state);
    });
    a.appendChild(rm);
    wrap.appendChild(a);
  });
}

function tickClock() {
  const now = new Date();
  const hh = String(now.getHours()).padStart(2, '0');
  const mm = String(now.getMinutes()).padStart(2, '0');
  const ss = String(now.getSeconds()).padStart(2, '0');
  $('clock').textContent = `${hh}:${mm}:${ss}`;
  $('date').textContent = now.toLocaleDateString('ru-RU', {
    weekday: 'long', day: 'numeric', month: 'long', year: 'numeric'
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  const state = await loadState();
  $('engine').value = state.engine;
  renderLinks(state);

  tickClock();
  setInterval(tickClock, 1000);
  $('q').focus();

  $('searchForm').addEventListener('submit', (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (!q) return;
    const engine = $('engine').value;
    state.engine = engine;
    saveState(state);
    const isUrl = /^(https?:\/\/|[\w-]+(\.[\w-]+)+)/i.test(q) && !q.includes(' ');
    if (isUrl) {
      location.href = normalizeUrl(q);
    } else {
      location.href = ENGINES[engine] + encodeURIComponent(q);
    }
  });

  $('engine').addEventListener('change', () => {
    state.engine = $('engine').value;
    saveState(state);
  });

  $('btnAdd').addEventListener('click', async () => {
    const t = $('linkTitle').value.trim();
    const u = $('linkUrl').value.trim();
    if (!u) return;
    state.links.push({ t: t || u, u: normalizeUrl(u) });
    await saveState(state);
    $('linkTitle').value = '';
    $('linkUrl').value = '';
    renderLinks(state);
  });

  $('btnOptions').addEventListener('click', () => chrome.runtime.openOptionsPage());
  $('btnExt').addEventListener('click', () => chrome.tabs.create({ url: 'chrome://extensions' }));

  // «/» — фокус в поиск
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && document.activeElement !== $('q') &&
        document.activeElement.tagName !== 'INPUT') {
      e.preventDefault();
      $('q').focus();
    }
  });
});
