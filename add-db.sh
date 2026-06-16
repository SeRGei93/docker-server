#!/usr/bin/env bash
set -euo pipefail

# Работаем из папки скрипта, где лежит docker-compose.yml
cd "$(dirname "$0")"

# Создаёт в общем postgres отдельную БД + пользователя для одного сервиса.
# Идемпотентно: можно запускать повторно. Пароль задаётся аргументом
# или генерируется и печатается один раз.
#
#   ./add-db.sh <db_name> <user> [password]

usage() { echo "использование: ./add-db.sh <db_name> <user> [password]"; exit 1; }

DB="${1:-}"; USER="${2:-}"; PASS="${3:-}"
if [ -z "$DB" ] || [ -z "$USER" ]; then usage; fi

# Имя суперпользователя (пароль не нужен — внутри контейнера socket = trust).
SUPER=postgres
if [ -f .env ]; then
  v="$(grep -E '^POSTGRES_USER=' .env | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)"
  [ -n "$v" ] && SUPER="$v"
fi

# postgres должен быть запущен и принимать соединения.
if ! docker compose exec -T postgres pg_isready -U "$SUPER" -d postgres >/dev/null 2>&1; then
  echo "✗ postgres не запущен/не отвечает — сначала ./up.sh"; exit 1
fi

psql_super() { docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$SUPER" -d postgres "$@"; }

# 1. Роль. Если есть — пароль трогаем только когда он передан явно.
ROLE_EXISTS="$(psql_super -tAc "SELECT 1 FROM pg_roles WHERE rolname='${USER}'" | tr -d '[:space:]')"
GEN=0
if [ "$ROLE_EXISTS" != "1" ]; then
  if [ -z "$PASS" ]; then
    PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24)"
    GEN=1
  fi
  psql_super -c "CREATE ROLE \"${USER}\" LOGIN PASSWORD '${PASS}';"
  echo "→ создана роль '${USER}'"
else
  echo "✓ роль '${USER}' уже существует"
  if [ -n "$PASS" ]; then
    psql_super -c "ALTER ROLE \"${USER}\" WITH LOGIN PASSWORD '${PASS}';"
    echo "→ пароль роли обновлён"
  fi
fi

# 2. База (CREATE DATABASE нельзя внутри транзакции/DO — через createdb).
if [ "$(psql_super -tAc "SELECT 1 FROM pg_database WHERE datname='${DB}'" | tr -d '[:space:]')" != "1" ]; then
  docker compose exec -T postgres createdb -U "$SUPER" -O "${USER}" "${DB}"
  echo "→ создана БД '${DB}' (владелец ${USER})"
else
  echo "✓ БД '${DB}' уже существует"
fi

# 3. Изоляция: к этой БД может подключаться только её владелец.
psql_super <<SQL
REVOKE CONNECT ON DATABASE "${DB}" FROM PUBLIC;
GRANT ALL PRIVILEGES ON DATABASE "${DB}" TO "${USER}";
SQL

# 4. pgvector в этой базе (образ pgvector/pgvector содержит расширение).
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$SUPER" -d "${DB}" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null
echo "→ расширение vector включено в '${DB}'"

echo
echo "✓ готово: БД '${DB}', пользователь '${USER}'"
if [ "$GEN" = 1 ]; then
  echo "  пароль (сохраните — больше не покажу): ${PASS}"
  echo "  строка подключения (изнутри сети shared-db):"
  echo "    postgres://${USER}:${PASS}@postgres:5432/${DB}"
else
  echo "  строка подключения (изнутри сети shared-db):"
  echo "    postgres://${USER}:<password>@postgres:5432/${DB}"
fi
