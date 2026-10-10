#!/usr/bin/env bash
# ============================================================
#  СУВЕРЕННЫЙ УЗЕЛ — DDNS: домашний узел сам держит DNS актуальным
#  (Путь Б: узел живёт у детей дома, IP у провайдера динамический)
#
#  Что делает: узнаёт текущий публичный IP этой машины и обновляет
#  в Cloudflare записи  A @ (proxied, путь T2)  и  A direct (dns-only, для T1/T3).
#  Требует: ddns.env рядом (DOMAIN + CF_TOKEN), домен уже добавлен в Cloudflare.
#
#  Установка на постоянку (один раз):
#    sudo cp ddns-update.sh ddns.env /opt/sovereign-node/
#    sudo chmod +x /opt/sovereign-node/ddns-update.sh
#    (crontab -l 2>/dev/null; echo "*/5 * * * * /opt/sovereign-node/ddns-update.sh >> /var/log/ddns.log 2>&1") | crontab -
#  Дальше он работает вечно и о себе не просит.
# ============================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/ddns.env" ] || { echo "НЕТ ddns.env рядом"; exit 1; }
set -a; source "$DIR/ddns.env"; set +a

[ -n "${DOMAIN:-}" ]     || { echo "DOMAIN пуст в ddns.env"; exit 1; }
[ -n "${CF_TOKEN:-}" ]   || { echo "CF_TOKEN пуст в ddns.env"; exit 1; }

API="https://api.cloudflare.com/client/v4"
H="Authorization: Bearer ${CF_TOKEN}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

IP4=$(curl -fsS4 --max-time 15 https://api.ipify.org 2>/dev/null || true)
IP6=$(curl -fsS6 --max-time 15 https://api64.ipify.org 2>/dev/null || true)
[ -n "$IP4" ] || [ -n "$IP6" ] || { echo "$TS нет сети, пропускаю"; exit 0; }

ZJ=$(curl -fsS --max-time 15 -H "$H" "$API/zones?name=${DOMAIN}" 2>/dev/null) || { echo "$TS зона недоступна"; exit 0; }
ZID=$(echo "$ZJ" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["result"][0]["id"] if d["result"] else "")')
[ -n "$ZID" ] || { echo "$TS зона ${DOMAIN} не найдена (ещё не добавлена?)"; exit 0; }

upsert() { # $1=type  $2=name  $3=content  $4=proxied(true/false)
  local TYPE="$1" NAME="$2" CONTENT="$3" PROXIED="$4"
  [ -n "$CONTENT" ] || return 0
  local REC_ID
  REC_ID=$(curl -fsS --max-time 15 -H "$H" "$API/zones/${ZID}/dns_records?type=${TYPE}&name=${NAME}.${DOMAIN}" 2>/dev/null \
    | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["result"][0]["id"] if d["result"] else "")' || true)
  local BODY="{\"type\":\"${TYPE}\",\"name\":\"${NAME}\",\"content\":\"${CONTENT}\",\"proxied\":${PROXIED},\"ttl\":1}"
  if [ -n "$REC_ID" ]; then
    curl -fsS --max-time 15 -X PATCH -H "$H" -H "Content-Type: application/json" \
      -d "$BODY" "$API/zones/${ZID}/dns_records/${REC_ID}" >/dev/null \
      && echo "$TS ${TYPE} ${NAME} -> ${CONTENT} (обновлено)" \
      || echo "$TS ${TYPE} ${NAME} -> ОШИБКА PATCH"
  else
    curl -fsS --max-time 15 -X POST -H "$H" -H "Content-Type: application/json" \
      -d "$BODY" "$API/zones/${ZID}/dns_records" >/dev/null \
      && echo "$TS ${TYPE} ${NAME} -> ${CONTENT} (создано)" \
      || echo "$TS ${TYPE} ${NAME} -> ОШИБКА POST"
  fi
}

if [ "$(curl -fsS --max-time 15 -H "$H" "$API/zones/${ZID}" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["status"])')" = "active" ]; then
  upsert "A" "@" "$IP4" "true"
  upsert "A" "direct" "$IP4" "false"
  upsert "AAAA" "@" "$IP6" "true"
else
  echo "$TS зона ещё не активна (NS не сменились) — записи не трогаю"
fi
