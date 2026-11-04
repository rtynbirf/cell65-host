#!/usr/bin/env python3
"""Конвертер hosts-файла → правила declarativeNetRequest (Chrome MV3).

Принимает hosts-файл (0.0.0.0 domain / 127.0.0.1 domain / ||domain^ / домены)
и выдаёт JSON-файл с DNR-правилами вида:

  [{"id": N, "priority": 1, "action": {"type": "block"},
    "condition": {"requestDomains": ["a.com", "b.com", ...]}}, ...]

Правила сгруппированы в чанки по --chunk доменов (запросDomains в одном
правиле). Лимиты Chrome (docs: declarativeNetRequest): 30 000 динамических
правил на расширение (Chrome 121+), до 100 статических наборов.
Планируйте: 30 000 / --chunk правил максимум.

Использование:
  python3 hosts_to_dnr.py --in packs/hosts-starter.txt --out rules.json \
      [--chunk 1000] [--base-id 1] [--allowlist exc1,exc2]
"""
import argparse
import json
import re
from pathlib import Path

HOSTNAME_RE = re.compile(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')


def parse_hosts(text):
    out = set()
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        idx = line.find('#')
        if idx == 0:
            continue
        if idx > 0:
            line = line[:idx]
        line = line.strip()
        if not line or line.startswith('!') or line.startswith('//') or line.startswith('@@'):
            continue
        for tok in line.split():
            d = tok.lower()
            if d.startswith('||'):
                d = d[2:]
            if d.endswith('^'):
                d = d[:-1]
            while d.startswith('.'):
                d = d[1:]
            if d.startswith('*.'):
                d = d[2:]
            if re.match(r'^\d{1,3}(\.\d{1,3}){3}$', d):
                continue
            if '/' in d or ':' in d:
                continue
            if not HOSTNAME_RE.match(d):
                continue
            out.add(d)
    return sorted(out)


def main():
    ap = argparse.ArgumentParser(description='hosts → DNR rules (Chrome MV3)')
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', dest='out', required=True)
    ap.add_argument('--chunk', type=int, default=1000)
    ap.add_argument('--base-id', type=int, default=1)
    ap.add_argument('--allowlist', default='', help='через запятую; эти домены и их поддомены исключаются')
    args = ap.parse_args()

    allow = [d.strip().lower() for d in args.allowlist.split(',') if d.strip()]
    domains = parse_hosts(Path(args.inp).read_text(encoding='utf-8'))
    domains = [d for d in domains if not any(d == e or d.endswith('.' + e) for e in allow)]

    rules = []
    rid = args.base_id
    for i in range(0, len(domains), args.chunk):
        rules.append({
            'id': rid,
            'priority': 1,
            'action': {'type': 'block'},
            'condition': {'requestDomains': domains[i:i + args.chunk]}
        })
        rid += 1

    Path(args.out).write_text(
        json.dumps(rules, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'OK: {args.out} · доменов={len(domains)} правил={len(rules)} '
          f'чанк={args.chunk} base_id={args.base_id}')


if __name__ == '__main__':
    main()
