#!/usr/bin/env bash
set -euo pipefail

# Работаем из папки скрипта, где лежит docker-compose.yml
cd "$(dirname "$0")"

# 1. Общая внешняя сеть edge (создаётся один раз, переиспользуется всеми проектами)
if docker network inspect edge >/dev/null 2>&1; then
  echo "✓ сеть 'edge' уже существует"
else
  echo "→ создаю сеть 'edge'"
  docker network create edge
fi

# 2. Боевой Caddyfile (не в git) — создаём из шаблона при первом запуске
if [ ! -f Caddyfile ]; then
  echo "→ создаю Caddyfile из Caddyfile.example (отредактируйте email и домены)"
  cp Caddyfile.example Caddyfile
fi

# 3. Папки для сертификатов/конфига (bind-mount в ./storage)
mkdir -p storage/data storage/config

# 4. Поднимаем Caddy
echo "→ поднимаю Caddy"
docker compose up -d

echo
echo "✓ готово"
echo "  логи:          docker compose logs -f caddy"
echo "  проверка сети: docker network inspect edge"
