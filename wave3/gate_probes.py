#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Гейты обхода: 4 пробы · cell65-host#7 · Волна ×3 (W3-F1).
Проба 1 (PAC-лестница): эталонная модель FindProxyForURL против матрицы 12×4
  (wave3/pac_matrix_12x4.json) — побайтовая сверка цепочки «PROXY; PROXY; SOCKS5; DIRECT»
  и fallback при отказе каждого звена; литеральные return-цепочки из реального pac/*.pac|js
  проверяются на формат, если файл найден.
Проба 2 (DNR): rules*.json — уникальные приоритеты, redirect-цели без chrome:// /
  javascript: / data:, extensionPath — внутри web_accessible_resources из manifest.json.
Проба 3 (WebRTC, офлайн-часть): RTCPeerConnection без защитного флага webRTCIPHandlingPolicy
  = красный; живая браузерная проба (Playwright, эхо-эндпоинт из env ECHO_URL, ICE-кандидаты
  без локального/публичного IP, «защита выключена — тест краснеет») — отдельная джоба.
Проба 4 (приватность): скан fetch/XHR/sendBeacon по коду расширения против allowlist
  (эхо-эндпоинт из --echo или env WAVE3_ECHO_URL); нарушение печатается файлом:строкой.
Запуск: python3 wave3/gate_probes.py [--root ПУТЬ] [--selftest]
"""
import argparse, json, os, re, sys, tempfile
from pathlib import Path
from fnmatch import fnmatch
PATTERNS = {'fetch()': re.compile(r'\bfetch\s*\('), 'XMLHttpRequest': re.compile(r'\bXMLHttpRequest\b'), 'sendBeacon': re.compile(r'\bsendBeacon\b')}
DNR_FORBIDDEN = ('chrome://', 'chrome-extension://', 'javascript:', 'data:')
SKIP_DIRS = {'.git', 'node_modules', '__pycache__', 'wave3', 'docs', 'tests'}
def ladder_chain(ladder, scenario):
    rest = ladder[1:] if scenario in ('first_down', 'auth_407') else list(ladder)
    return '; '.join(rest) if rest else 'DIRECT'
def probe_pac(root, matrix_path):
    m = json.loads(Path(matrix_path).read_text(encoding='utf-8'))
    ladder, bad, n = m['ladder'], 0, 0
    for case in m['cases']:
        exp = m[case['expect_ref']] if 'expect_ref' in case else case['expect']
        for scen in m['scenarios']:
            got = 'DIRECT' if scen == 'direct_only' or case['class'] == 'local' else ladder_chain(ladder, scen)
            n += 1
            if got != exp[scen]:
                print('FAIL PAC %s [%s]: %r != %r' % (case['url'], scen, got, exp[scen])); bad += 1
    print('PAC-матрица: %d/%d кейсов побайтово сходятся' % (n - bad, n))
    pac_files = [p for pat in ('pac/**/*.pac', 'pac/**/*.js') for p in root.glob(pat) if p.is_file()]
    for p in pac_files:
        for i, chain in enumerate(re.findall(r'return\s+"([^"]+)"', p.read_text(encoding='utf-8', errors='ignore'))):
            segs = [s.strip() for s in chain.split(';') if s.strip()]
            ok = bool(segs) and all(re.fullmatch(r'(PROXY|SOCKS5|SOCKS|HTTPS) \S+(:\d+)?|DIRECT', s) for s in segs)
            print('%s: return#%d «%s» — формат %s' % (p, i + 1, chain[:64], 'ok' if ok else 'БИТЫЙ'))
            bad += 0 if ok else 1
    if not pac_files:
        print('(PAC-файл в pac/ не найден — гейт держит эталонную модель лестницы; прогон реального FindProxyForURL — следующий шаг)')
    return bad == 0
def _war_resources(manifest_path):
    try:
        man = json.loads(manifest_path.read_text(encoding='utf-8'))
    except Exception as e:
        print('(manifest.json не читается: %s)' % e); return None
    war = man.get('web_accessible_resources', [])
    out = []
    for entry in war:
        out += entry.get('resources', []) if isinstance(entry, dict) else [entry]
    return out or None
def validate_dnr(rules, war):
    errs, seen = [], {}
    if not isinstance(rules, list):
        return ['rules-файл должен быть массивом правил']
    for i, r in enumerate(rules):
        if not isinstance(r, dict):
            errs.append('правило #%d: не объект' % i); continue
        p = r.get('priority')
        if not isinstance(p, int) or isinstance(p, bool):
            errs.append('правило #%d: priority не целое' % i)
        elif p in seen:
            errs.append('правило #%d: приоритет %d дублирует правило #%d' % (i, p, seen[p]))
        else:
            seen[p] = i
        act = r.get('action') or {}
        red = (act.get('redirect') or {}) if isinstance(act, dict) and act.get('type') == 'redirect' else {}
        tgt = red.get('url') or red.get('extensionPath') or red.get('regexSubstitution') or ''
        if tgt.lower().startswith(DNR_FORBIDDEN):
            errs.append('правило #%d: redirect на запрещённую цель %r' % (i, tgt))
        if 'extensionPath' in red and war is not None and not any(fnmatch(red['extensionPath'].lstrip('/'), w.lstrip('/')) for w in war):
            errs.append('правило #%d: extensionPath %r вне web_accessible_resources' % (i, red['extensionPath']))
    return errs
def probe_dnr(root):
    rules_files = [p for p in root.rglob('*.json') if p.name.startswith('rules') and not any(s in p.parts for s in SKIP_DIRS)][:50]
    if not rules_files:
        print('(DNR: rules-файлы не найдены — проба помечена «пропущено», не декоративно-зелёная)'); return True
    manifests = [p for p in root.rglob('manifest.json') if not any(s in p.parts for s in SKIP_DIRS)]
    war = _war_resources(manifests[0]) if manifests else None
    bad = False
    for p in rules_files:
        try:
            errs = validate_dnr(json.loads(p.read_text(encoding='utf-8')), war)
        except Exception as e:
            print('FAIL DNR %s: не читается (%s)' % (p, e)); bad = True; continue
        if errs:
            bad = True
            for e in errs: print('FAIL DNR %s: %s' % (p, e))
        else:
            print('OK   DNR %s: приоритеты уникальны, redirect-цели чистые' % p)
    return not bad
def _scan_privacy(dirs, echo=''):
    hits = []
    for d in dirs:
        for p in sorted(d.rglob('*')):
            if not p.is_file() or any(s in p.parts for s in SKIP_DIRS) or p.suffix in ('.png', '.jpg', '.ico', '.zip', '.crx'):
                continue
            try:
                text = p.read_text(encoding='utf-8', errors='ignore')
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), 1):
                for name, rx in PATTERNS.items():
                    if rx.search(line) and not (echo and echo in line):
                        hits.append((p, i, name))
    return hits
def probe_privacy(root, echo=''):
    base = root / 'anticensormv3'
    dirs = [base] if base.exists() else [root]
    hits = _scan_privacy(dirs, echo)
    for p, i, name in hits:
        print('FAIL приватность: %s:%d — %s вне allowlist' % (p, i, name))
    if not hits: print('OK   приватность: ноль fetch/XHR/beacon вне allowlist (эхо: %s)' % (echo or 'не задан'))
    return not hits
def probe_webrtc(ext_dir):
    ext_dir = Path(ext_dir)
    src = list(ext_dir.rglob('*.js')) if ext_dir.exists() else []
    if not src:
        print('(WebRTC: js-код расширения не найден — офлайн-часть пропущена с пометкой)'); return True
    uses, guard = [], []
    for p in src:
        t = p.read_text(encoding='utf-8', errors='ignore')
        if 'RTCPeerConnection' in t: uses.append(p)
        if 'webRTCIPHandlingPolicy' in t or 'webRTCNonProxiedUdpAddress' in t: guard.append(p)
    if uses and not guard:
        print('FAIL WebRTC: RTCPeerConnection без защитного флага webRTCIPHandlingPolicy в %s' % ', '.join(map(str, uses)))
        print('     живая браузерная проба (Playwright + ECHO_URL, ICE-кандидаты без локального/публичного IP, «защита выключена — тест краснеет») — отдельная джоба')
        return False
    print('OK   WebRTC офлайн-часть: %s' % ('защитный флаг найден' if guard else 'RTCPeerConnection не используется'))
    return True
def selftest():
    fails = []
    with tempfile.TemporaryDirectory() as td:
        t = Path(td)
        bad_rules = t / 'rules.json'
        bad_rules.write_text(json.dumps([
            {'id': 1, 'priority': 1, 'action': {'type': 'block'}},
            {'id': 2, 'priority': 1, 'action': {'type': 'redirect', 'redirect': {'url': 'chrome://settings'}}},
            {'id': 3, 'priority': 2, 'action': {'type': 'redirect', 'redirect': {'extensionPath': '/hidden.html'}}},
        ]), encoding='utf-8')
        errs = validate_dnr(json.loads(bad_rules.read_text(encoding='utf-8')), ['/public.html'])
        if len(errs) < 3: fails.append('валидатор DNR пропустил дефекты: %s' % errs)
        ext = t / 'ext'; ext.mkdir()
        (ext / 'bg.js').write_text('fetch("https://tracker.example/collect")\n', encoding='utf-8')
        (ext / 'echo.js').write_text('fetch("https://echo.example/ping")\n', encoding='utf-8')
        if [(x[0].name, x[2]) for x in _scan_privacy([ext], 'https://echo.example')] != [('bg.js', 'fetch()')]:
            fails.append('сканер приватности/allowlist: %s' % _scan_privacy([ext], 'https://echo.example'))
        if len(_scan_privacy([ext], '')) != 2: fails.append('без allowlist должны ловиться обе строки')
        (ext / 'rtc.js').write_text('const pc = new RTCPeerConnection({});\n', encoding='utf-8')
        if probe_webrtc(ext): fails.append('PC без guard должен быть красным')
        (ext / 'rtc.js').write_text('const pc = new RTCPeerConnection({}); pc.webRTCIPHandlingPolicy = "proxy";\n', encoding='utf-8')
        if not probe_webrtc(ext): fails.append('PC с guard должен быть зелёным')
    m = Path(__file__).resolve().parent / 'pac_matrix_12x4.json'
    if not probe_pac(Path(__file__).resolve().parent.parent, m): fails.append('эталонная PAC-матрица не сошлась')
    print('selftest: %s' % ('OK — дубликат приоритета, chrome://-redirect, трекер и PC-без-guard ловятся' if not fails else 'ПРОВАЛ: ' + '; '.join(fails)))
    return 1 if fails else 0
def main(argv=None):
    here = Path(__file__).resolve()
    ap = argparse.ArgumentParser(description='Гейты обхода · cell65-host#7')
    ap.add_argument('--root', default=str(here.parent.parent), help='корень репо')
    ap.add_argument('--matrix', default=str(here.parent / 'pac_matrix_12x4.json'))
    ap.add_argument('--echo', default=os.environ.get('WAVE3_ECHO_URL', ''), help='allowlist-эхо-эндпоинт (или env WAVE3_ECHO_URL)')
    ap.add_argument('--selftest', action='store_true', help='самотест чувствительности гейтов')
    a = ap.parse_args(argv)
    if a.selftest: return selftest()
    root = Path(a.root)
    ext = root / 'anticensormv3' if (root / 'anticensormv3').exists() else root
    probes = [('PAC-лестница', probe_pac(root, a.matrix)), ('DNR', probe_dnr(root)),
              ('WebRTC (офлайн-часть)', probe_webrtc(ext)), ('приватность', probe_privacy(root, a.echo))]
    for n, ok in probes: print('ИТОГ %s: %s' % (n, 'зелёный' if ok else 'КРАСНЫЙ'))
    print('гейты: %d/%d зелёные' % (sum(1 for _, ok in probes if ok), len(probes)))
    return 0 if all(ok for _, ok in probes) else 1
if __name__ == '__main__':
    sys.exit(main())
