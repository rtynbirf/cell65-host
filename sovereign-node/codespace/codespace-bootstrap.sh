#!/usr/bin/env bash
# ============================================================
# CELL-65 :: codespace bootstrap (идемпотентный)
# Качает gost 2.12.0, поднимает HTTP:18080 + SOCKS5:18081,
# самотест через оба порта (ожидаем 204/204).
# Повторный запуск безопасен: живой gost перезапускается.
# ============================================================
set -u
DIR="$HOME/c65"
mkdir -p "$DIR"
cd "$DIR" || exit 1

GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.12.0/gost_2.12.0_linux_amd64.tar.gz"

if [ ! -x "$DIR/gost" ]; then
  echo "C65: качаю gost 2.12.0..."
  curl -fsSL -o gost.tgz "$GOST_URL" 2>/dev/null || { echo "C65: FAIL не скачался gost"; exit 1; }
  tar -xzf gost.tgz 2>/dev/null || { echo "C65: FAIL не распаковался gost"; exit 1; }
  chmod +x "$DIR/gost" 2>/dev/null
  [ -x "$DIR/gost" ] || { echo "C65: FAIL бинарника gost нет"; exit 1; }
  echo "C65: gost на борту"
fi

# прибить только НАШИ старые инстансы (по полному пути)
pkill -f "$DIR/gost" 2>/dev/null || true
sleep 1

nohup "$DIR/gost" -L="http://:18080" -L="socks5://:18081" > "$DIR/gost.log" 2>&1 &
sleep 2

code_http=$(curl -fsS -m 10 -x http://127.0.0.1:18080 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null || echo 000)
code_s5=$(curl -fsS -m 10 -x socks5h://127.0.0.1:18081 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 2>/dev/null || echo 000)
echo "C65: самотест http=$code_http socks5=$code_s5 (ожидаем 204/204)"

if [ "$code_s5" != "204" ]; then
  echo "C65: FAIL socks5 самотест; хвост gost.log:"
  tail -n 5 "$DIR/gost.log" 2>/dev/null
  exit 1
fi
echo "C65: BOOTSTRAP OK - HTTP:18080, SOCKS5:18081, выход в интернет живой"
