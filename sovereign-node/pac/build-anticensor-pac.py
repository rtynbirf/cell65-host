#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build-anticensor-pac.py — сборка PAC-скрипта «Антицензор» (СУВЕРЕННЫЙ УЗЕЛ, cell65-host).

Что делает:
  1. Берёт свежий список заблокированных доменов (экспорт реестра АнтиЗапрета),
     кэширует его рядом с собой; можно подсунуть свой файл через --list.
  2. Упаковывает домены в фильтр Блума прямо внутри самодостаточного PAC-файла
     (~0.5 МБ — влезает в лимит Windows для PAC-скриптов).
  3. Проверяет сборку тем же алгоритмом, что будет работать в браузере
     (зеркальная реализация хешей), и измеряет фактическую долю ложных срабатываний.

Запуск:
    python3 build-anticensor-pac.py --proxy VPS_IP:3128
    python3 build-anticensor-pac.py --proxy 198.51.100.7:3128 --out anticensor.pac
    python3 build-anticensor-pac.py --proxy 127.0.0.1:3128 --list ./domains-export.txt

Формат --proxy: HOST:PORT. В PAC попадёт строка:
    'PROXY HOST:PORT; DIRECT'   (браузер при первом заходе спросит логин/пароль,
                                 если на прокси включена аутентификация — см. enable-pac-endpoint.sh)
"""
import argparse, math, os, random, sys, time, urllib.request, urllib.error

SRC_URL = "https://antizapret.prostovpn.org/domains-export.txt"
CACHE_NAME = "domains-export.txt"
UA = "sovereign-node pac builder"
_LN2 = 0.6931471805599453

def fetch_list(path_out: str) -> str:
    req = urllib.request.Request(SRC_URL, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    with open(path_out, "wb") as f:
        f.write(data)
    return path_out

def load_domains(path: str):
    domains = set()
    bad = 0
    with open(path, "rb") as f:
        raw = f.read().decode("utf-8", errors="replace")
    for line in raw.splitlines():
        d = line.strip().lower().rstrip(".")
        if not d or d.startswith("#") or d.startswith("//"):
            continue
        ok = all(ch.isalnum() or ch in "-." for ch in d) and "." in d
        if ok and all(lbl and not lbl.startswith("-") and not lbl.endswith("-") for lbl in d.split(".")):
            domains.add(d)
        else:
            bad += 1
    return sorted(domains), bad

# ---- зеркальная реализация хешей (обязана совпадать с JS до бита) ----
def fnv_pair(s: str):
    h1, h2 = 2166136261, 3750763034
    for ch in s:
        b = ord(ch) & 0xFF
        h1 = ((h1 ^ b) * 16777619) & 0xFFFFFFFF
        h2 = ((h2 ^ b) * 16777619) & 0xFFFFFFFF
    h2 |= 1
    return h1, h2

def bit_set(bits: bytearray, idx: int):
    bits[idx >> 3] |= 1 << (idx & 7)

def bit_get(bits: bytes, idx: int) -> bool:
    return (bits[idx >> 3] >> (idx & 7)) & 1 == 1

def build_bloom(domains, fp_rate: float):
    n = len(domains)
    m = int(-n * math.log(fp_rate) / (_LN2 * _LN2))
    m = max(1024, m + (4 - m % 4) % 4)          # кратность 4 битам (hex-упаковка)
    k = max(1, min(16, int(round(m / n * _LN2))))
    bits = bytearray((m + 7) // 8)
    for d in domains:
        h1, h2 = fnv_pair(d)
        for j in range(k):
            bit_set(bits, ((h1 + j * h2) & 0xFFFFFFFF) % m)
    return bytes(bits), m, k

def bloom_query(bits: bytes, s: str, m: int, k: int) -> bool:
    h1, h2 = fnv_pair(s)
    return all(bit_get(bits, ((h1 + j * h2) & 0xFFFFFFFF) % m) for j in range(k))

JS_TMPL = """\
// ============================================================
// PAC «Антицензор» — СУВЕРЕННЫЙ УЗЕЛ (rtynbirf/cell65-host)
// Сгенерирован: {gen_date}
// Доменов в фильтре: {n} | бит: {m} | хешей: {k} | ложные срабатывания: ~{fp}%
// Источник списка: {src}
// Фильтр Блума: ложное срабатывание = незаблокированный домен пойдёт
//   через прокси (безвредно: прокси его просто откроет). Пропусков нет.
// ПЕРЕСБОРКА СО СВОИМ ПРОКСИ:
//   python3 build-anticensor-pac.py --proxy HOST:PORT   (см. README-PAC.md)
// ГРАНИЦЫ: PAC маршрутизирует, но сам ничего не шифрует; работает только
//   с доменными блокировками (IP-блокировки — не его случай). IE не поддерживается.
// ============================================================
'use strict';

// <<< ЕДИНСТВЕННАЯ СТРОКА ДЛЯ ПРАВКИ: куда слать заблокированные домены >>>
var PAC_PROXY = '{proxy_line}'; // {proxy_note}

var PAC_M = {m};
var PAC_K = {k};
var PAC_BITS = '{hex}';

function _pacNib(idx) {{
  var p = idx & 7;
  var c = PAC_BITS.charCodeAt((idx >> 3) * 2 + (1 - (p >> 2)));
  var n = c < 58 ? c - 48 : c - 87; // '0'-'9' : 'a'-'f'
  return (n >> (idx & 3)) & 1;
}}

function _pacHit(s) {{
  var h1 = 2166136261, h2 = 3750763034;
  for (var i = 0; i < s.length; i++) {{
    var b = s.charCodeAt(i) & 255;
    h1 = Math.imul((h1 ^ b) >>> 0, 16777619) >>> 0;
    h2 = Math.imul((h2 ^ b) >>> 0, 16777619) >>> 0;
  }}
  h2 = (h2 | 1) >>> 0;
  for (var j = 0; j < PAC_K; j++) {{
    var idx = ((h1 + Math.imul(j, h2)) >>> 0) % PAC_M;
    if (!_pacNib(idx)) return false;
  }}
  return true;
}}

function FindProxyForURL(url, host) {{
  var h = String(host || '').toLowerCase();
  if (h.length > 1 && h.charAt(h.length - 1) === '.') h = h.slice(0, -1);
  var L = h.split('.');
  for (var i = 0; i < L.length; i++) {{
    var suf = L.slice(i).join('.');
    if (suf && _pacHit(suf)) return PAC_PROXY;
  }}
  return 'DIRECT';
}}
"""

def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--proxy", required=True, help="HOST:PORT прокси для заблокированных доменов")
    ap.add_argument("--out", default="anticensor.pac", help="имя итогового PAC-файла")
    ap.add_argument("--list", default=None, help="готовый список доменов (офлайн-режим)")
    ap.add_argument("--fp-rate", type=float, default=0.001, help="целевая доля ложных срабатываний (0.001 = 0.1%%)")
    args = ap.parse_args()

    proxy = args.proxy.strip()
    if "/" in proxy or "@" in proxy or " " in proxy or ":" not in proxy:
        print("ОШИБКА: --proxy ожидается как HOST:PORT, например 198.51.100.7:3128", file=sys.stderr)
        sys.exit(2)
    host_p, _, port_p = proxy.rpartition(":")
    if not host_p or not port_p.isdigit():
        print("ОШИБКА: не разобрал HOST:PORT", file=sys.stderr)
        sys.exit(2)
    proxy_line = f"PROXY {host_p}:{port_p}; DIRECT"

    here = os.path.dirname(os.path.abspath(__file__))
    list_path = args.list or os.path.join(here, CACHE_NAME)
    if args.list or not os.path.exists(list_path):
        print("==> качаю реестр доменов:", SRC_URL)
        try:
            list_path = fetch_list(list_path)
        except Exception as e:
            print(f"ОШИБКА: не смог скачать список ({e}).", file=sys.stderr)
            print("Подсказка: скачай вручную и запусти с --list путь_к_файлу", file=sys.stderr)
            sys.exit(1)

    domains, bad = load_domains(list_path)
    if not domains:
        print("ОШИБКА: список пуст", file=sys.stderr)
        sys.exit(1)
    print(f"==> доменов к упаковке: {len(domains)} (отброшено не-доменов: {bad})")

    bits, m, k = build_bloom(domains, args.fp_rate)
    hexs = bits.hex()
    pac = JS_TMPL.format(
        gen_date=time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime()),
        n=len(domains), m=m, k=k, fp=round(args.fp_rate * 100, 3),
        src=SRC_URL, proxy_line=proxy_line,
        proxy_note="впиши свой HOST:PORT или пересобери через build-anticensor-pac.py",
        hex=hexs,
    )
    out_path = args.out if os.path.isabs(args.out) else os.path.join(here, args.out)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(pac)
    size_kb = os.path.getsize(out_path) / 1024

    # --- верификация зеркальным алгоритмом ---
    dset = set(domains)
    rnd = random.Random(20261031)
    sample_pos = rnd.sample(domains, min(1000, len(domains)))
    misses = [d for d in sample_pos if not bloom_query(bits, d, m, k)]

    words = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima "
             "mike november oscar papa quebec romeo sierra tango uniform victor whiskey "
             "xray yankee zulu polar orbit lunar solar terra nova vortex prism").split()
    test_neg, fp_hits = 0, 0
    for a in words:
        for b in words:
            for tld in ("com", "net", "org", "io", "dev"):
                h = f"{a}-{b}.{tld}"
                if h in dset:
                    continue
                test_neg += 1
                if bloom_query(bits, h, m, k):
                    fp_hits += 1
    fp_real = fp_hits / test_neg * 100 if test_neg else 0.0

    print(f"==> фильтр: {m} бит, {k} хешей, hex {len(hexs)} символов")
    print(f"==> файл: {out_path} ({size_kb:.0f} КБ)")
    print(f"==> пропусков заблокированных из выборки 1000: {len(misses)}")
    print(f"==> ложные срабатывания на {test_neg} не-блокированных: {fp_hits} ({fp_real:.3f}%)")
    print(f"==> строка прокси в PAC: {proxy_line}")
    if size_kb > 1900:
        print("ВНИМАНИЕ: файл близок к лимиту Windows (~2 МБ) — уменьши --fp-rate", file=sys.stderr)
    if misses:
        print("ОШИБКА: есть пропуски — сборка некорректна", file=sys.stderr)
        sys.exit(1)
    print("ГОТОВО.")

if __name__ == "__main__":
    main()
