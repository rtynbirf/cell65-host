#!/usr/bin/env bash
# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — PAC-эндпоинт «Антицензор» (опционально)
#  Добавляет четвёртый вход к узлу: mixed (HTTP+SOCKS) :3128 с логином/паролем.
#  Нужен, чтобы PAC-скрипт водил через твой узел устройства БЕЗ sing-box
#  (браузеры родственников, рабочие ноутбуки, чужие машины).
#  Запуск на VPS:  sudo bash enable-pac-endpoint.sh
#  Идемпотентно: повторный запуск обновляет логин/пароль и рестартует службу.
# ============================================================
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ЗАПУСКАЙ ЧЕРЕЗ sudo"; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if [ -f "$DIR/server.env" ]; then
  echo "==> Параметры из server.env"
  set -a; source "$DIR/server.env"; set +a
fi

PAC_PORT="${PAC_PORT:-3128}"
PAC_USER="${PAC_USER:-pac}"
CONF=/etc/sovereign-node/config.json
[ -f "$CONF" ] || { echo "нет $CONF — сначала поставь узел (install-server.sh)"; exit 1; }

# Пароль: из окружения/server.env (PAC_PASSWORD) либо генерируем один раз и сохраняем
if [ -z "${PAC_PASSWORD:-}" ]; then
  ENVF="$DIR/server.env"
  if [ -f "$ENVF" ] && grep -q '^PAC_PASSWORD=' "$ENVF"; then
    PAC_PASSWORD="$(grep '^PAC_PASSWORD=' "$ENVF" | head -1 | cut -d= -f2- | tr -d '\"')"
    echo "==> PAC_PASSWORD найден в server.env"
  else
    PAC_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)"
    if [ -f "$ENVF" ]; then
      echo "PAC_PASSWORD=${PAC_PASSWORD}" >> "$ENVF"
      chmod 600 "$ENVF"
      echo "==> PAC_PASSWORD сгенерирован и дописан в server.env (там же, где остальные ключи)"
    else
      echo "==> PAC_PASSWORD сгенерирован: ${PAC_PASSWORD}"
      echo "    СОХРАНИ ЕГО — больше не покажется (server.env рядом не лежал)"
    fi
  fi
fi

echo "==> 1/3 Рендер inbound pac-mixed :${PAC_PORT} (пользователь: ${PAC_USER})"
python3 - "$CONF" "$PAC_PORT" "$PAC_USER" "$PAC_PASSWORD" <<'PY'
import json, sys
conf_path, port, user, password = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
conf = json.load(open(conf_path, encoding="utf-8"))
inb = conf.setdefault("inbounds", [])
entry = next((x for x in inb if x.get("tag") == "pac-mixed"), None)
if entry is None:
    entry = {"type": "mixed", "tag": "pac-mixed", "listen": "::", "listen_port": port}
    inb.append(entry)
entry["listen"] = entry.get("listen", "::")
entry["listen_port"] = port
entry["users"] = [{"username": user, "password": password}]
json.dump(conf, open(conf_path + ".new", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("    inbound pac-mixed готов (во временный файл, до проверки)")
PY

echo "==> 2/3 Проверка конфига sing-box"
if /usr/local/bin/sing-box check -c "${CONF}.new"; then
  mv "${CONF}.new" "$CONF"
  chmod 600 "$CONF"
else
  rm -f "${CONF}.new"
  echo "КОНФИГ НЕ ПРОШЁЛ ПРОВЕРКУ — рабочая конфигурация не тронута"; exit 1
fi

echo "==> 3/3 Файрвол и перезапуск"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${PAC_PORT}/tcp" >/dev/null 2>&1 || true
fi
systemctl restart sovereign-node
sleep 2
systemctl --no-pager -l status sovereign-node | head -4 || true

IP_SHOWN="${VPS_IP:-<VPS_IP>}"
echo
echo "================= PAC-ЭНДПОИНТ ГОТОВ ================="
echo "Прокси:    ${IP_SHOWN}:${PAC_PORT} (HTTP + SOCKS, логин ${PAC_USER})"
echo "Пересборка PAC: python3 build-anticensor-pac.py --proxy ${IP_SHOWN}:${PAC_PORT}"
echo "Браузер сам спросит логин/пароль при первом заходе на заблокированный сайт."
echo "Снять эндпоинт: удали inbound с тегом pac-mixed из $CONF и перезапусти службу."
echo "======================================================"
