# docker-server

Edge-прокси (**Caddy**) для нескольких docker-проектов на одном сервере.
Caddy слушает `80/443`, терминирует TLS (авто Let's Encrypt) и маршрутизирует
по домену в бэкенд каждого проекта через общую docker-сеть `edge`.

```
              :80 / :443
                  │
              ┌───▼────┐
              │ Caddy  │  ← единственный слушает 80/443, держит TLS
              └─┬───┬──┘
        edge ───┘   └─── edge        (общая внешняя сеть)
        ┌────────┐   ┌────────┐
        │projA-app│  │projB-app│ ...  ← бэкенды, без публикации портов
        └────────┘   └────────┘
```

## Запуск

```bash
./up.sh          # создаёт сеть edge (если нет) и поднимает Caddy
```

## Добавить проект

1. Положить проект в `projects/<name>/` (свой `docker-compose.yml`).
2. Подключить **бэкенд** проекта к сети `edge`:

   ```yaml
   services:
     app:
       container_name: <name>-app     # = цель reverse_proxy в Caddyfile
       restart: unless-stopped
       networks: [default, edge]      # ports наружу НЕ публикуем
     db:
       networks: [default]            # внутреннее — только на default
   networks:
     default:
     edge:
       external: true
   ```

3. Поднять проект: `cd projects/<name> && docker compose up -d`.

4. Добавить домен в `Caddyfile` скриптом — он сам проверит, что контейнер
   запущен, в сети `edge` и порт отвечает, затем допишет блок, провалидирует
   конфиг и перечитает Caddy:

   ```bash
   ./add-site.sh example.com <name>-app:<port>
   ```

   Либо вручную — блок в `Caddyfile` + `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`.

## Важно

- Сеть `edge` создаётся `up.sh` **до** запуска проектов (в их compose она `external: true`).
- На `edge` подключаем **только бэкенды**; БД/кэши/воркеры — на приватной `default`.
- Сертификаты и ключ ACME-аккаунта лежат в `./storage/data` (bind-mount `/data`) — **не удалять** (иначе упрётесь в лимиты перевыпуска Let's Encrypt). Бэкап = `tar czf caddy-backup.tgz storage/`. Папка `storage/` в `.gitignore` — секреты не коммитим.
- Домены должны резолвиться на IP сервера, порты 80/443 открыты — иначе Let's Encrypt не выдаст сертификат.
- Содержимое `projects/` не версионируется в этом репозитории (см. `.gitignore`).
- Боевой `Caddyfile` **не в git** (постоянно меняется через `add-site.sh`) — версионируется только шаблон `Caddyfile.example`. `up.sh` создаёт `Caddyfile` из шаблона при первом запуске; правьте в нём `email` и домены.
