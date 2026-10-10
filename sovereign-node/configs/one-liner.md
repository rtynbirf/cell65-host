# СУВЕРЕННЫЙ УЗЕЛ — серверный установщик (семейная раздача)

Чистый скрипт установки серверной части. Секретов не содержит — они приходят
отдельно от владельца узла (файлом `server.env` или переменными окружения).

## Вариант 1 — классический (два файла)

```bash
scp install-server.sh server.env root@IP_СЕРВЕРА:/root/
ssh root@IP_СЕРВЕРА "bash install-server.sh"
```

## Вариант 2 — однострочник (родители присылают ОДНО сообщение)

Родители подставляют свои значения из `server.env` и присылают ребёнку строку:

```bash
curl -fsSL https://raw.githubusercontent.com/rtynbirf/singulyar/main/sovereign-node/server/install-server.sh \
  | sudo env \
    VLESS_UUID=SET_ME_UUID \
    REALITY_PRIVATE_KEY=SET_ME_REALITY_PRIVATE_KEY \
    REALITY_SHORT_ID=SET_ME_SHORT_ID \
    HY2_PASSWORD=SET_ME_HY2_PASSWORD \
    HY2_OBFS=SET_ME_HY2_OBFS \
    bash
```

Скрипт сам: скачает последний sing-box, сгенерирует сертификат, запишет конфиг
(Reality :443/tcp + WS :8443/tcp + Hysteria2 :443/udp), включит BBR,
зарегистрирует systemd-службу `sovereign-node` с автоперезапуском.

После установки ребёнок проверяет `systemctl status sovereign-node` и
присылает родителям обратно только IP сервера.
