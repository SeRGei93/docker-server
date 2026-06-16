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
        edge ───┘   └─── edge        (общая публичная маршрутная сеть)
        ┌────────┐   ┌────────┐
        │projA-app│  │projB-app│ ...  ← бэкенды, без публикации портов
        └───┬────┘   └────┬───┘
   shared-db│             │shared-db  (общая приватная сеть к БД)
            └──────┬──────┘
              ┌────▼─────┐
              │ postgres │  ← общий, портов наружу нет
              └──────────┘
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
       container_name: <name>-app          # = цель reverse_proxy в Caddyfile
       restart: unless-stopped
       networks: [default, edge, shared-db] # ports наружу НЕ публикуем
                                            # shared-db — только если нужен общий postgres
     db:
       networks: [default]                 # свой приватный сервис — только на default
   networks:
     default:
     edge:
       external: true
     shared-db:                            # добавлять, только если app ходит в общий postgres
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

## Общий postgres

Корневой `docker-compose.yml` поднимает общий `postgres` на отдельной приватной
сети `shared-db` (НЕ на `edge`). Порты наружу не публикуются — подключиться может
только контейнер, явно добавленный в `shared-db`.

1. Пароль БД — в `.env` (создаётся из `.env.example` при первом `./up.sh`,
   в git не попадает). Обязательно задайте `POSTGRES_PASSWORD`.
2. Бэкенду проекта, которому нужна БД, добавьте сеть `shared-db` (см. пример выше).
3. Строка подключения изнутри контейнера: хост = имя контейнера `postgres`,
   порт = внутренний `5432`:

   ```
   postgres://<POSTGRES_USER>:<POSTGRES_PASSWORD>@postgres:5432/<POSTGRES_DB>
   ```

Если проекту нужна изолированная собственная БД (а не общая) — поднимайте её
в его же compose на `default`, как раньше.

## Важно

- Сети `edge` и `shared-db` создаёт `up.sh` **до** запуска проектов (в их compose обе `external: true`).
- На `edge` подключаем **только бэкенды**; приватные БД/кэши/воркеры проекта — на `default`; к общему postgres — через `shared-db`.
- БД на `edge` **не вешаем**: `edge` — публичная маршрутная сеть, она плоско видна всем проектам.
- Пароль postgres лежит в `.env` (в `.gitignore`); данные БД — в `./storage/pg`, входят в бэкап `storage/`.
- Сертификаты и ключ ACME-аккаунта лежат в `./storage/data` (bind-mount `/data`) — **не удалять** (иначе упрётесь в лимиты перевыпуска Let's Encrypt). Бэкап = `tar czf caddy-backup.tgz storage/`. Папка `storage/` в `.gitignore` — секреты не коммитим.
- Домены должны резолвиться на IP сервера, порты 80/443 открыты — иначе Let's Encrypt не выдаст сертификат.
- Содержимое `projects/` не версионируется в этом репозитории (см. `.gitignore`).
- Боевой `Caddyfile` **не в git** (постоянно меняется через `add-site.sh`) — версионируется только шаблон `Caddyfile.example`. `up.sh` создаёт `Caddyfile` из шаблона при первом запуске; правьте в нём `email` и домены.
