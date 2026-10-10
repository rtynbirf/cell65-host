#!/usr/bin/env bash
# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — серверная установка (VPS, Ubuntu/Debian)
#  Запуск:  sudo bash install-server.sh
#  Ставит ОДИН бинарь sing-box со всеми транспортами:
#    T1 VLESS+Reality :443/tcp   (маска SNI_MASK)
#    T2 VLESS+XHTTP   :8443/tcp  (готов к приёму через Cloudflare CDN)
#    T3 Hysteria2     :443/udp   (QUIC, obfs salamander)
#  Идемпотентно: повторный запуск просто обновляет конфиг и рестартует сервис.
# ============================================================
set -euo pipefail

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
XPATH="${XHTTP_PATH:-/xh}"
RP="${REALITY_PORT:-443}"; XP="${XHTTP_PORT:-8443}"; HP="${HY2_PORT:-443}"
CN_DOMAIN="${DOMAIN:-$SNI}"

echo "==> 1/7 Архитектура"
case "$(uname -m)" in
  x86_64)  GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  *) echo "Неизвестная архитектура: $(uname -m)"; exit 1 ;;
esac

echo "==> 2/7 Версия sing-box"
VER=""
VER=$(curl -fsSL --max-time 20 "https://github.com/SagerNet/sing-box/releases.atom" 2>/dev/null | grep -oP '(?<=tag/releases/v)[^<]+' | head -1 || true)
if [ -z "$VER" ]; then
  VER=$(curl -fsSL --max-time 20 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"v\K[^"]+' || true)
fi
[ -n "$VER" ] || { echo "Не смог узнать версию (нет сети до GitHub?)"; exit 1; }
echo "    v$VER"

echo "==> 3/7 Загрузка и установка бинаря"
mkdir -p /tmp/sbx && cd /tmp/sbx
curl -fsSL --retry 3 -o sb.tgz "https://github.com/SagerNet/sing-box/releases/download/v${VER}/sing-box-${VER}-linux-${GOARCH}.tar.gz"
tar -xzf sb.tgz
install -m 0755 "sing-box-${VER}-linux-${GOARCH}/sing-box" /usr/local/bin/sing-box
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
      "tag": "vless-xhttp-t2",
      "listen": "::",
      "listen_port": ${XP},
      "users": [ { "name": "sovereign", "uuid": "${UUID_}" } ],
      "tls": {
        "enabled": true,
        "server_name": "${CN_DOMAIN}",
        "certificate_path": "/etc/sovereign-node/cert.pem",
        "key_path": "/etc/sovereign-node/key.pem"
      },
      "transport": { "type": "xhttp", "path": "${XPATH}" }
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
Description=Sovereign Node (sing-box: Reality + XHTTP + Hysteria2)
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
echo "T2 XHTTP   : ${XP}/tcp   путь ${XPATH}   ждёт домен: ${CN_DOMAIN}"
echo "T3 Hysteria2: ${HP}/udp  obfs включён"
echo "Порты держать открытыми: ${RP}/tcp, ${XP}/tcp, ${HP}/udp"
if [ -z "${DOMAIN}" ]; then
  echo "DOMAIN пуст: T2 пока не активен на клиенте — это нормально."
  echo "Когда появится домен: впиши его в server.env, перезапусти этот скрипт,"
  echo "затем на Windows запусти provision-edge.ps1 и install-sovereign-node.ps1."
fi
echo "======================================================"
