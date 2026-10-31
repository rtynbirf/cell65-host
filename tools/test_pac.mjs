// Функциональный тест генератора PAC «Антицензор» (node, без браузера).
import { buildPacData, buildProxyConfig, normalizeDomains } from '../anticensormv3/lib/pac-engine.js';
import { QUICK_PACS } from '../anticensormv3/lib/defaults.js';
import vm from 'node:vm';

let failed = 0;
function expect(cond, label) {
  if (cond) { console.log('  OK  ', label); }
  else { failed++; console.error('  FAIL', label); }
}

const cfg = {
  mode: 'pac',
  pacScope: 'list',
  proxyScheme: 'socks5',
  proxyHost: '127.0.0.1',
  proxyPort: 1080,
  bypass: ['localhost', '127.0.0.1', '[::1]', '<local>'],
  antizensor: ['Twitter.com', 'x.com', 'facebook.com', '*.example.org', 'https://instagram.com/'],
  exceptions: ['mail.example.ru', '*.corp']
};

const pac = buildPacData(cfg);

// Запускаем PAC в песочнице с полифиллом shExpMatch (как в браузере).
const sandbox = {
  shExpMatch(str, pattern) {
    const rx = new RegExp('^' + pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
    return rx.test(str);
  },
  console
};
vm.createContext(sandbox);
vm.runInContext(pac, sandbox);
const Find = sandbox.FindProxyForURL;

console.log('== PAC list-mode ==');
expect(Find('https://twitter.com/home', 'twitter.com').startsWith('SOCKS5 127.0.0.1:1080'), 'twitter.com -> прокси');
expect(Find('https://x.com/', 'x.com').startsWith('SOCKS5'), 'x.com -> прокси');
expect(Find('https://www.instagram.com/', 'www.instagram.com').startsWith('SOCKS5'), 'поддомен instagram -> прокси (из URL-замусоренного входа)');
expect(Find('https://cdn.example.org/a', 'cdn.example.org').startsWith('SOCKS5'), 'wildcard *.example.org -> прокси');
expect(Find('https://example.org/', 'example.org') === 'DIRECT', 'сам example.org без wildcard -> DIRECT');
expect(Find('http://github.com/', 'github.com') === 'DIRECT', 'github.com (не в списке) -> DIRECT');
expect(Find('https://mail.example.ru/', 'mail.example.ru') === 'DIRECT', 'исключение mail.example.ru -> DIRECT (даже при wildcard *.example.org)');
expect(Find('https://www.bank.corp/', 'www.bank.corp') === 'DIRECT', 'wildcard-исключение *.corp -> DIRECT');
expect(Find('http://localhost:3000/', 'localhost') === 'DIRECT', 'localhost -> DIRECT');
expect(Find('http://192.168.1.1/', '192.168.1.1') === 'DIRECT', '192.168.1.1 -> DIRECT');
expect(Find('http://10.0.0.5/', '10.0.0.5') === 'DIRECT', '10.0.0.5 -> DIRECT');
expect(Find('http://172.16.0.9/', '172.16.0.9') === 'DIRECT', '172.16.0.9 -> DIRECT');
expect(Find('https://[::1]:8080/', '[::1]') === 'DIRECT', '[::1] -> DIRECT');
expect(Find('https://FE80::1/', 'fe80::1') === 'DIRECT', 'fe80::1 -> DIRECT');

console.log('== PAC all-mode ==');
const pacAll = buildPacData({ ...cfg, pacScope: 'all' });
const sb2 = { shExpMatch: sandbox.shExpMatch };
vm.createContext(sb2);
vm.runInContext(pacAll, sb2);
expect(sb2.FindProxyForURL('https://wikipedia.org/', 'wikipedia.org').startsWith('SOCKS5'), 'all: wikipedia -> прокси');
expect(sb2.FindProxyForURL('https://mail.example.ru/', 'mail.example.ru') === 'DIRECT', 'all: исключение всё равно DIRECT');

console.log('== fixed_servers (global) ==');
const g = buildProxyConfig({ ...cfg, mode: 'global' });
expect(g.mode === 'fixed_servers', 'mode=fixed_servers');
expect(g.rules.singleProxy.scheme === 'socks5' && g.rules.singleProxy.port === 1080, 'singleProxy socks5:1080');
expect(g.rules.fallbackProxy.host === '127.0.0.1', 'fallbackProxy задан');
expect(g.rules.bypassList.includes('<local>'), 'bypassList содержит <local>');
expect(g.rules.bypassList.includes('mail.example.ru'), 'bypassList включает исключения');

console.log('== direct ==');
expect(buildProxyConfig({ mode: 'direct' }).mode === 'direct', 'mode=direct');

console.log('== normalizeDomains ==');
const nd = normalizeDomains(['  HTTPS://Example.COM/path ', '||Blocked.ORG^', '.dot.com', '', '***', '*.ok.io', 'dup.com', 'dup.com']);
expect(JSON.stringify(nd) === JSON.stringify(['example.com', 'blocked.org', 'dot.com', '*.ok.io', 'dup.com']), 'нормализация/дедуп: ' + JSON.stringify(nd));

console.log('== PAC: mandatory/структура chrome.proxy ==');
const pc = buildProxyConfig(cfg);
expect(pc.mode === 'pac_script' && pc.pacScript.mandatory === false && typeof pc.pacScript.data === 'string', 'pac_script {data, mandatory:false}');

console.log('== PAC url-режим (внешний PAC, напр. «АнтиЗапрет») ==');
const u = buildProxyConfig({ mode: 'pac', pacSource: 'url', pacUrl: 'https://antizapret.prostovpn.org/proxy.pac' });
expect(u.mode === 'pac_script' && u.pacScript.url === 'https://antizapret.prostovpn.org/proxy.pac' && u.pacScript.mandatory === false, 'pacScript {url, mandatory:false}');
expect(u.pacScript.data === undefined, 'data не задаётся в url-режиме');
const l = buildProxyConfig({ mode: 'pac', pacSource: 'local', pacUrl: 'https://x.example/proxy.pac' });
expect(typeof l.pacScript.data === 'string' && l.pacScript.url === undefined, 'local: data есть, url нет');
const eEmpty = buildProxyConfig({ mode: 'pac', pacSource: 'url', pacUrl: '' });
expect(typeof eEmpty.pacScript.data === 'string', 'url-режим с пустым URL → откат на локальный PAC');
expect(QUICK_PACS.antizapret.urls.length === 2 && QUICK_PACS.antizapret.urls.every((x) => /^https:\/\//.test(x)), 'QUICK_PACS.antizapret: 2 https-URL');

if (failed) {
  console.error(`\n${failed} ТЕСТОВ УПАЛО`);
  process.exit(1);
}
console.log('\nВСЕ PAC-ТЕСТЫ ЗЕЛЁНЫЕ');
