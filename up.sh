#!/usr/bin/env bash
set -euo pipefail

# Работаем из папки скрипта, где лежит docker-compose.yml
cd "$(dirname "$0")"

# 1. Общие внешние сети (создаются один раз, переиспользуются всеми проектами)
#    edge      — публичная маршрутная сеть Caddy ↔ бэкенды
#    shared-db — приватная сеть к общему postgres (только нужные бэкенды)
for net in edge shared-db; do
  if docker network inspect "$net" >/dev/null 2>&1; then
    echo "✓ сеть '$net' уже существует"
  else
    echo "→ создаю сеть '$net'"
    docker network create "$net"
  fi
done

# 2. Боевой Caddyfile (не в git) — создаём из шаблона при первом запуске
if [ ! -f Caddyfile ]; then
  echo "→ создаю Caddyfile из Caddyfile.example (отредактируйте email и домены)"
  cp Caddyfile.example Caddyfile
fi

# 3. .env (не в git) — пароль postgres и пр.; создаём из шаблона при первом запуске
if [ ! -f .env ]; then
  echo "→ создаю .env из .env.example — ОБЯЗАТЕЛЬНО задайте POSTGRES_PASSWORD"
  cp .env.example .env
fi

# 4. Папки для сертификатов/конфига Caddy и данных postgres (bind-mount в ./storage)
mkdir -p storage/data storage/config storage/pg

# 5. Поднимаем Caddy + postgres
echo "→ поднимаю Caddy и postgres"
docker compose up -d

echo
echo "✓ готово"
echo "  логи:          docker compose logs -f caddy"
echo "  проверка сети: docker network inspect edge"
