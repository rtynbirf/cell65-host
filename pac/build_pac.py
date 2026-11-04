#!/usr/bin/env python3
"""«Антицензор» — сборщик standalone PAC-скрипта.

Читает packs/antizensor-list.txt и packs/exceptions.txt и генерирует
pac/antizensor.pac — самодостаточный Proxy Auto-Config файл, который можно
подключить: в Chrome/Edge/Firefox (URL или содержимое), в системных
настройках прокси Windows/macOS, или через расширение «Антицензор MV3».

Логика идентична lib/pac-engine.js расширения (синхронизируется вручную).

Лучшие практики (официальные доки Chromium/Chrome, см. docs/SOURCES.md):
  * без dnsResolve()/isInNet() — только строковые проверки по хосту;
  * ES5-совместимое тело PAC;
  * bypass локальных/приватных сетей (RFC1918, link-local, localhost);
  * возврат "SCHEME host:port; DIRECT" — откат на DIRECT при сбое прокси.

Использование:
  python3 build_pac.py [--proxy "socks5 127.0.0.1:1080"] [--scope list|all]
                       [--list packs/antizensor-list.txt]
                       [--exceptions packs/exceptions.txt]
                       [--out pac/antizensor.pac]
"""
import argparse
import datetime
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

HOSTNAME_RE = re.compile(r'^[a-z0-9.*-]+$')


def normalize_domains(lines):
    out, seen = [], set()
    for raw in lines:
        d = raw.strip().lower()
        if not d or d.startswith('#'):
            continue
        d = re.sub(r'^[a-z][a-z0-9+.-]*://', '', d)
        d = d.split('/')[0].split(':')[0]
        if d.startswith('||'):
            d = d[2:]
        if d.endswith('^'):
            d = d[:-1]
        while d.startswith('.'):
            d = d[1:]
        if not d or d == '*' or not HOSTNAME_RE.match(d):
            continue
        if d in seen:
            continue
        seen.add(d)
        out.append(d)
    return out


PAC_TEMPLATE = """// «Антицензор» PAC — сгенерирован pac/build_pac.py
// {generated_at}
// Прокси: {proxy_str}; резерв — DIRECT
// Список: {n_proxied} доменов; исключения: {n_exceptions} доменов
// Источник списков: packs/antizensor-list.txt, packs/exceptions.txt
// Логика и источники лучших практик: docs/SOURCES.md в репозитории.
var AC65_CHAIN = '{proxy_chain}';
var AC65_SCOPE_ALL = {scope_all};
var AC65_PROXIED = {proxied_json};
var AC65_EXCEPTIONS = {exceptions_json};
function ac65IsPrivateHost(h) {{
  if (h === 'localhost' || (h.length > 10 && h.slice(h.length - 10) === '.localhost')) return true;
  var isIp = (h.charCodeAt(0) >= 48 && h.charCodeAt(0) <= 57);
  if (isIp) {{
    var p = h.split('.');
    if (p.length !== 4) return false;
    if (p[0] === '10' || p[0] === '127' || p[0] === '0') return true;
    if (p[0] === '192' && p[1] === '168') return true;
    if (p[0] === '172' && p[1] >= 16 && p[1] <= 31) return true;
    if (p[0] === '169' && p[1] === '254') return true;
    return false;
  }}
  if (h.indexOf(':') !== -1) {{
    if (h === '::1' || h === '[::1]') return true;
    if (h.indexOf('fe80') === 0) return true;
    if (h.indexOf('fc') === 0 || h.indexOf('fd') === 0) return true;
    return false;
  }}
  return false;
}}
function ac65Match(h, list) {{
  for (var i = 0; i < list.length; i++) {{
    var d = list[i];
    if (d.charCodeAt(0) === 42) {{
      if (shExpMatch(h, d)) return true;
    }} else if (h === d) {{
      return true;
    }} else if (h.length > d.length + 1 &&
               h.charCodeAt(h.length - d.length - 1) === 46 &&
               h.slice(h.length - d.length) === d) {{
      return true;
    }}
  }}
  return false;
}}
function FindProxyForURL(url, host) {{
  host = (host || '').toLowerCase();
  if (!host) return 'DIRECT';
  if (ac65IsPrivateHost(host)) return 'DIRECT';
  if (ac65Match(host, AC65_EXCEPTIONS)) return 'DIRECT';
  if (AC65_SCOPE_ALL || ac65Match(host, AC65_PROXIED)) return AC65_CHAIN;
  return 'DIRECT';
}}
"""


def main():
    ap = argparse.ArgumentParser(description='Сборка standalone PAC «Антицензор»')
    ap.add_argument('--proxy', default='socks5 127.0.0.1:1080',
                    help='напр. "socks5 127.0.0.1:1080", "http 10.0.0.2:3128"')
    ap.add_argument('--scope', choices=['list', 'all'], default='list')
    ap.add_argument('--list', default=str(REPO / 'packs' / 'antizensor-list.txt'))
    ap.add_argument('--exceptions', default=str(REPO / 'packs' / 'exceptions.txt'))
    ap.add_argument('--out', default=str(REPO / 'pac' / 'antizensor.pac'))
    args = ap.parse_args()

    proxied = normalize_domains(Path(args.list).read_text(encoding='utf-8').splitlines())
    exceptions = normalize_domains(Path(args.exceptions).read_text(encoding='utf-8').splitlines())

    proxy_str = args.proxy.strip().upper()
    proxy_chain = f'{proxy_str}; DIRECT'

    pac = PAC_TEMPLATE.format(
        generated_at=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
        proxy_str=proxy_str,
        proxy_chain=proxy_chain,
        scope_all='true' if args.scope == 'all' else 'false',
        proxied_json=json.dumps(proxied, ensure_ascii=False),
        exceptions_json=json.dumps(exceptions, ensure_ascii=False),
        n_proxied=len(proxied),
        n_exceptions=len(exceptions),
    )
    Path(args.out).write_text(pac, encoding='utf-8', newline='\n')
    print(f'OK: {args.out} · proxied={len(proxied)} exceptions={len(exceptions)} '
          f'scope={args.scope} proxy={proxy_str}')


if __name__ == '__main__':
    main()
