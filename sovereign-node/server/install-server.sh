#!/usr/bin/env bash
# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — серверная установка (VPS, Ubuntu/Debian)
#  Запуск:  sudo bash install-server.sh
#  Ставит ОДИН бинарь sing-box со всеми транспортами:
#    T1 VLESS+Reality :443/tcp   (маска SNI_MASK)
#    T2 VLESS+WS     :8443/tcp  (готов к приёму через Cloudflare CDN)
#    T3 Hysteria2     :443/udp   (QUIC, obfs salamander)
#    T4 AnyTLS       :2053/tcp  (чистый TLS 1.3 + паддинг против TLS-in-TLS)
#  Идемпотентно: повторный запуск просто обновляет конфиг и рестартует сервис.
# ============================================================
set -euo pipefail

# --- Закреплённая версия sing-box (аудит supply-chain, WP-F) ---
# Почему закрепляем, а не берём «последний релиз»: динамический выбор версии
# невоспроизводим (два запуска в разные дни ставят разные бинари) и превращает
# «curl | bash» в открытую дверь для подмены релиза на стороне апстрима.
# Поэтому версия зафиксирована, а её SHA-256 вшит ниже и проверяется ДО
# распаковки. Обновление — осознанное действие: поменять версию + дайджесты.
# checksums.txt релизы sing-box НЕ публикуют (проверено на v1.10.0..v1.14.4),
# поэтому для закреплённой версии дайджесты вшиты сюда.
SING_BOX_PINNED="1.14.4"
# SHA-256 официальных тарболлов релиза v1.14.4 (SagerNet/sing-box, linux):
SB_SHA256_amd64="699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968"
SB_SHA256_arm64="436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26"

[ "$(id -u)" -eq 0 ] || { echo "ЗАПУСКАЙ ЧЕРЕЗ sudo"; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)"
if [ -f "$DIR/server.env" ]; then
  echo "==> Конфиг из server.env"
  set -a; source "$DIR/server.env"; set +a
else
  echo "==> server.env не найден — беру параметры из окружения (режим однострочника)"
  : "${VLESS_UUID:?нет VLESS_UUID (передай через env или положи server.env рядом)}"
  : "${REALITY_PRIVATE_KEY:?нет REALITY_PRIVATE_KEY}"
  : "${REALITY_SHORT_ID:?нет REALITY_SHORT_ID}"
  : "${HY2_PASSWORD:?нет HY2_PASSWORD}"
  : "${HY2_OBFS:?нет HY2_OBFS}"
fi

SNI="${SNI_MASK:-www.microsoft.com}"
T2PATH="${T2_PATH:-/xh}"
RP="${REALITY_PORT:-443}"; XP="${T2_PORT:-8443}"; HP="${HY2_PORT:-443}"; T4P="${T4_PORT:-2053}"
CN_DOMAIN="${DOMAIN:-$SNI}"

# T4 AnyTLS: пароль обязателен; пусто = генерируем и дописываем в server.env
AP="${ANYTLS_PASSWORD:-}"
if [ -z "$AP" ]; then
  AP=$(openssl rand -base64 18 | tr -d '/+=' || true)
  echo "==> ANYTLS_PASSWORD не задан — сгенерирован: $AP"
  if [ -f "$DIR/server.env" ]; then
    grep -q '^ANYTLS_PASSWORD=' "$DIR/server.env" 2>/dev/null || echo "ANYTLS_PASSWORD=${AP}" >> "$DIR/server.env"
    echo "    дописан в server.env — СКОПИРУЙ ЕГО в node.env клиента (иначе T4 не поднимется)."
  else
    echo "    (server.env рядом отсутствует — пароль только в этом выводе)"
  fi
fi

echo "==> 1/7 Архитектура"
case "$(uname -m)" in
  x86_64)  GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *) echo "Неизвестная архитектура: $(uname -m)"; exit 1 ;;
esac

echo "==> 2/7 Версия sing-box"
# Приоритет: env SING_BOX_VER (или старый SINGBOX_VERSION) > закреплённая версия.
# Чужую версию можно задать, но проверка целостности всё равно обязательна
# (см. шаг 3/7): либо checksums.txt этого релиза, либо явный ALLOW_UNPINNED=1.
SB_VER="${SING_BOX_VER:-${SINGBOX_VERSION:-$SING_BOX_PINNED}}"
SB_VER="${SB_VER#v}"
if [ "$SB_VER" = "$SING_BOX_PINNED" ]; then
  echo "    v$SB_VER (закреплённая версия, SHA-256 вшит в скрипт)"
else
  echo "    v$SB_VER (переопределено вручную — потребуется checksums.txt или ALLOW_UNPINNED=1)"
fi

echo "==> 3/7 Загрузка и установка бинаря (с проверкой SHA-256)"
SB_TGZ="sing-box-${SB_VER}-linux-${GOARCH}.tar.gz"
mkdir -p /tmp/sbx && cd /tmp/sbx
curl -fsSL --retry 3 -o sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/${SB_TGZ}"

# Проверка целостности ДО распаковки — fail closed: не совпало/нечем проверить —
# ничего не ставим.
SB_EXPECT=""
if [ "$SB_VER" = "$SING_BOX_PINNED" ]; then
  case "$GOARCH" in
    amd64) SB_EXPECT="$SB_SHA256_amd64" ;;
    arm64) SB_EXPECT="$SB_SHA256_arm64" ;;
  esac
else
  # Чужая версия: тянем checksums.txt из ТОГО ЖЕ релиза.
  if curl -fsSL --retry 2 -o checksums.txt \
       "https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/checksums.txt"; then
    SB_EXPECT=$(grep -E "^[0-9a-fA-F]{64}[[:space:]]+\*?${SB_TGZ}$" checksums.txt | head -1 | cut -d' ' -f1 || true)
    [ -n "$SB_EXPECT" ] || { echo "ОШИБКА: в checksums.txt релиза v${SB_VER} нет строки для ${SB_TGZ}"; exit 1; }
  fi
fi

if [ -n "$SB_EXPECT" ]; then
  if echo "$SB_EXPECT  sb.tgz" | sha256sum -c - >/dev/null 2>&1; then
    echo "    SHA-256 OK: ${SB_EXPECT}"
  else
    echo "ОШИБКА: SHA-256 НЕ СОВПАЛ для v${SB_VER} linux-${GOARCH}." >&2
    echo "  Тарболл повреждён или подменён — установка прервана. Никакой бинарь не ставился." >&2
    exit 1
  fi
elif [ "${ALLOW_UNPINNED:-0}" = "1" ]; then
  echo "ВНИМАНИЕ: ALLOW_UNPINNED=1 — ставим v${SB_VER} БЕЗ проверки SHA-256 (checksums.txt у релиза нет)." >&2
  echo "  Это осознанный обход защиты: бинарь ставится на свой страх и риск." >&2
else
  echo "ОШИБКА: для v${SB_VER} нет ни вшитого дайджеста, ни checksums.txt в релизе." >&2
  echo "  Варианты: сними SING_BOX_VER (вернёшься к закреплённой версии)," >&2
  echo "  или явно разреши установку без проверки: ALLOW_UNPINNED=1 bash install-server.sh." >&2
  exit 1
fi

tar -xzf sb.tgz
install -m 0755 "sing-box-${SB_VER}-linux-${GOARCH}/sing-box" /usr/local/bin/sing-box
cd /; rm -rf /tmp/sbx
/usr/local/bin/sing-box version | head -1

echo "==> 4/7 Сертификат (self-signed, для T2/T3; CF работает в режиме Full)"
mkdir -p /etc/sovereign-node
openssl ecparam -genkey -name prime256v1 -out /etc/sovereign-node/key.pem 2>/dev/null
openssl req -new -x509 -key /etc/sovereign-node/key.pem -out /etc/sovereign-node/cert.pem \
  -days 3650 -subj "/CN=${CN_DOMAIN}" 2>/dev/null

echo "==> 5/7 Конфиг сервера"
UUID_="${VLESS_UUID}"; RPUB_CHECK=""; PRIV="${REALITY_PRIVATE_KEY}"; SID="${REALITY_SHORT_ID}"
HPW="${HY2_PASSWORD}"; OBFS="${HY2_OBFS}"

cat > /etc/sovereign-node/config.json <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-t1",
      "listen": "::",
      "listen_port": ${RP},
      "users": [ { "name": "sovereign", "uuid": "${UUID_}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${SNI}", "server_port": 443 },
          "private_key": "${PRIV}",
          "short_id": [ "${SID}" ]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-ws-t2",
      "listen": "::",
      "listen_port": ${XP},
      "users": [ { "name": "sovereign", "uuid": "${UUID_}" } ],
      "tls": {
        "enabled": true,
        "server_name": "${CN_DOMAIN}",
        "certificate_path": "/etc/sovereign-node/cert.pem",
        "key_path": "/etc/sovereign-node/key.pem"
      },
      "transport": { "type": "ws", "path": "${T2PATH}" }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-t3",
      "listen": "::",
      "listen_port": ${HP},
      "up_mbps": 200,
      "down_mbps": 200,
      "users": [ { "name": "sovereign", "password": "${HPW}" } ],
      "obfs": { "type": "salamander", "password": "${OBFS}" },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sovereign-node/cert.pem",
        "key_path": "/etc/sovereign-node/key.pem"
      },
      "masquerade": "https://${SNI}/"
    },
    {
      "type": "anytls",
      "tag": "anytls-t4",
      "listen": "::",
      "listen_port": ${T4P},
      "users": [ { "name": "sovereign", "password": "${AP}" } ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "certificate_path": "/etc/sovereign-node/cert.pem",
        "key_path": "/etc/sovereign-node/key.pem"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
chmod 600 /etc/sovereign-node/config.json /etc/sovereign-node/key.pem

/usr/local/bin/sing-box check -c /etc/sovereign-node/config.json \
  || { echo "КОНФИГ НЕ ПРОШЁЛ ПРОВЕРКУ"; exit 1; }

echo "==> 6/7 Ядро (BBR) и systemd"
SYS=/etc/sysctl.d/99-sovereign.conf
{ echo "net.core.default_qdisc=fq"; echo "net.ipv4.tcp_congestion_control=bbr"; echo "fs.file-max=1048576"; } > "$SYS"
sysctl --system >/dev/null 2>&1 || true

cat > /etc/systemd/system/sovereign-node.service <<EOF
[Unit]
Description=Sovereign Node (sing-box: Reality + WS/CDN + Hysteria2 + AnyTLS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sovereign-node/config.json
Restart=always
RestartSec=5
LimitNOFILE=1048576
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/sovereign-node

[Install]
WantedBy=multi-user.target
EOF

if command -v ufw >/dev/null 2>&1; then
  ufw allow "${RP}/tcp" >/dev/null 2>&1 || true
  ufw allow "${XP}/tcp" >/dev/null 2>&1 || true
  ufw allow "${HP}/udp" >/dev/null 2>&1 || true
  ufw allow "${T4P}/tcp" >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable sovereign-node >/dev/null 2>&1
systemctl restart sovereign-node
sleep 2

echo "==> 7/7 Статус"
systemctl --no-pager -l status sovereign-node | head -6 || true
echo
echo "================= ГОТОВО. КАРТА УЗЛА ================="
echo "T1 Reality : ${RP}/tcp   SNI-маска ${SNI}   short_id ${SID}"
echo "T2 WS      : ${XP}/tcp   путь ${T2PATH}   ждёт домен: ${CN_DOMAIN}"
echo "T3 Hysteria2: ${HP}/udp  obfs включён"
echo "T4 AnyTLS  : ${T4P}/tcp   пароль в server.env/node.env"
echo "Порты держать открытыми: ${RP}/tcp, ${XP}/tcp, ${HP}/udp, ${T4P}/tcp"
if [ -z "${DOMAIN}" ]; then
  echo "DOMAIN пуст: T2 пока не активен на клиенте — это нормально."
  echo "Когда появится домен: впиши его в server.env, перезапусти этот скрипт,"
  echo "затем на Windows запусти provision-edge.ps1 и install-sovereign-node.ps1."
fi
echo "======================================================"
