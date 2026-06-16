#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
CADDYFILE="./Caddyfile"
NETWORK="edge"

# боевой Caddyfile не в git — создаём из шаблона, если его ещё нет
[ -f "$CADDYFILE" ] || cp Caddyfile.example "$CADDYFILE"

usage() {
  echo "Использование: $0 <домен> <контейнер:порт>"
  echo "Пример:        $0 projecta.com projA-app:3000"
  exit 1
}

err() { echo "✗ $*" >&2; exit 1; }

# ── аргументы ─────────────────────────────────────────────
[ $# -eq 2 ] || usage
DOMAIN="$1"
TARGET="$2"

case "$TARGET" in
  *:*) ;;
  *) echo "✗ второй аргумент должен быть в формате контейнер:порт" >&2; usage ;;
esac
CONTAINER="${TARGET%%:*}"
PORT="${TARGET##*:}"

case "$PORT" in
  ''|*[!0-9]*) err "порт '$PORT' не число" ;;
esac

# ── 1. контейнер существует и запущен ─────────────────────
running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" \
  || err "контейнер '$CONTAINER' не найден"
[ "$running" = "true" ] || err "контейнер '$CONTAINER' есть, но не запущен"
echo "✓ контейнер '$CONTAINER' запущен"

# ── 2. контейнер подключён к сети edge ────────────────────
if ! docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' \
        "$CONTAINER" | grep -Fxq "$NETWORK"; then
  echo "✗ контейнер '$CONTAINER' не в сети '$NETWORK' — Caddy его не увидит" >&2
  echo "  быстро:    docker network connect $NETWORK $CONTAINER" >&2
  echo "  правильно: добавить сеть '$NETWORK' (external) в его docker-compose.yml" >&2
  exit 1
fi
echo "✓ контейнер в сети '$NETWORK'"

# ── 3. порт реально отвечает (DNS+TCP так же, как у Caddy) ─
if docker run --rm --network "$NETWORK" busybox \
     nc -z -w 3 "$CONTAINER" "$PORT" >/dev/null 2>&1; then
  echo "✓ порт $CONTAINER:$PORT доступен"
else
  err "порт $CONTAINER:$PORT недоступен (контейнер не слушает этот порт?)"
fi

# ── 4. домен ещё не добавлен ──────────────────────────────
esc_domain="${DOMAIN//./\\.}"
if [ -f "$CADDYFILE" ] && grep -qE "^[[:space:]]*${esc_domain}[[:space:]]*\{" "$CADDYFILE"; then
  err "домен '$DOMAIN' уже есть в $CADDYFILE"
fi

# ── 5. бэкап и добавление блока ───────────────────────────
cp "$CADDYFILE" "$CADDYFILE.bak"
cat >> "$CADDYFILE" <<EOF

$DOMAIN {
	reverse_proxy $CONTAINER:$PORT
}
EOF
echo "✓ блок добавлен (бэкап: $CADDYFILE.bak)"

# ── 6. валидация Caddyfile (без запущенного Caddy) ────────
if ! docker run --rm -v "$(pwd)/Caddyfile:/etc/caddy/Caddyfile:ro" \
       caddy:2-alpine validate --adapter caddyfile --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
  mv "$CADDYFILE.bak" "$CADDYFILE"
  err "Caddyfile невалиден — изменения откатил"
fi
echo "✓ Caddyfile валиден"

# ── 7. горячий reload, если Caddy запущен ─────────────────
if [ "$(docker inspect -f '{{.State.Running}}' caddy 2>/dev/null || true)" = "true" ]; then
  if docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
    echo "✓ Caddy перечитал конфиг"
  else
    echo "⚠ не удалось перечитать Caddy автоматически — сделайте вручную:"
    echo "  docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile"
  fi
else
  echo "ℹ Caddy не запущен — поднимите: ./up.sh"
fi

rm -f "$CADDYFILE.bak"
echo "✓ готово: $DOMAIN → $CONTAINER:$PORT"
