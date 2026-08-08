#!/usr/bin/env bash
# Recupera Cal.com desde los volúmenes existentes sin usar Redeploy Stack.
# La web se valida en la red interna antes de conectarla a Traefik.
set -euo pipefail

ENV_FILE="${1:-}"
APP_ID="cmpaiat5n0004qfa4r6m8l8rl"
WEB_CONTAINER="${APP_ID}-cal-web"
DB_CONTAINER="${APP_ID}-cal-db"
REDIS_CONTAINER="${APP_ID}-cal-redis"
DB_VOLUME="${APP_ID}cal-db-data"
REDIS_VOLUME="${APP_ID}cal-redis-data"
INTERNAL_NETWORK="cal-internal"
IMAGE="calcom/cal.com:v6.2.0"
FQDN="cal.hubstartidea.es"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -n "$ENV_FILE" ] || fail "uso: $0 /ruta/cal.env"
[ -f "$ENV_FILE" ] || fail "no existe $ENV_FILE"
[ "$(stat -c %a "$ENV_FILE")" = "600" ] || fail "$ENV_FILE debe tener modo 600"

for key in DATABASE_URL DATABASE_DIRECT_URL NEXTAUTH_SECRET CALENDSO_ENCRYPTION_KEY; do
  grep -q "^${key}=" "$ENV_FILE" || fail "falta $key"
done
for volume in "$DB_VOLUME" "$REDIS_VOLUME"; do
  docker volume inspect "$volume" >/dev/null 2>&1 || fail "falta volumen $volume"
done

DB_ENV=$(mktemp)
trap 'rm -f "$DB_ENV"' EXIT
chmod 600 "$DB_ENV"
grep -E '^POSTGRES_(USER|PASSWORD|DB)=' "$ENV_FILE" > "$DB_ENV"

docker network inspect "$INTERNAL_NETWORK" >/dev/null 2>&1 \
  || docker network create --internal "$INTERNAL_NETWORK" >/dev/null

if ! docker container inspect "$DB_CONTAINER" >/dev/null 2>&1; then
  docker run -d --name "$DB_CONTAINER" \
    --network "$INTERNAL_NETWORK" --network-alias cal-db \
    --restart unless-stopped --env-file "$DB_ENV" \
    -v "$DB_VOLUME:/var/lib/postgresql/data" \
    --health-cmd='pg_isready -U calcom -d calcom' \
    --health-interval=10s --health-timeout=5s --health-retries=6 \
    postgres:16-alpine >/dev/null
fi

if ! docker container inspect "$REDIS_CONTAINER" >/dev/null 2>&1; then
  docker run -d --name "$REDIS_CONTAINER" \
    --network "$INTERNAL_NETWORK" --network-alias cal-redis \
    --restart unless-stopped -v "$REDIS_VOLUME:/data" \
    redis:7-alpine redis-server --appendonly yes >/dev/null
fi

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null || true)" = healthy ] && break
  sleep 1
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER")" = healthy ] \
  || fail "PostgreSQL no está healthy"
docker exec "$REDIS_CONTAINER" redis-cli ping | grep -qx PONG || fail "Redis no responde"

docker pull "$IMAGE"
docker container inspect "$WEB_CONTAINER" >/dev/null 2>&1 \
  && fail "$WEB_CONTAINER ya existe; usa recreate-cal-web.py para actualizarlo"

docker run -d --name "$WEB_CONTAINER" \
  --network "$INTERNAL_NETWORK" --restart unless-stopped \
  --env-file "$ENV_FILE" \
  --health-cmd='wget --quiet --tries=1 --spider http://localhost:3000/' \
  --health-interval=30s --health-timeout=10s --health-retries=5 \
  --health-start-period=120s \
  -l traefik.enable=true \
  -l traefik.docker.network=coolify \
  -l "traefik.http.routers.cal-web.rule=Host(\`${FQDN}\`)" \
  -l traefik.http.routers.cal-web.entrypoints=websecure \
  -l traefik.http.routers.cal-web.tls=true \
  -l traefik.http.routers.cal-web.tls.certresolver=letsencrypt \
  -l traefik.http.routers.cal-web.service=cal-web \
  -l traefik.http.services.cal-web.loadbalancer.server.port=3000 \
  -l traefik.http.middlewares.cal-web-redirect.redirectscheme.scheme=https \
  -l traefik.http.middlewares.cal-web-redirect.redirectscheme.permanent=true \
  -l "traefik.http.routers.cal-web-http.rule=Host(\`${FQDN}\`)" \
  -l traefik.http.routers.cal-web-http.entrypoints=web \
  -l traefik.http.routers.cal-web-http.middlewares=cal-web-redirect \
  "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$WEB_CONTAINER" 2>/dev/null || true)" = healthy ] && break
  sleep 10
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$WEB_CONTAINER")" = healthy ] \
  || { docker logs --tail 100 "$WEB_CONTAINER" >&2; fail "Cal.com no está healthy"; }

docker network connect coolify "$WEB_CONTAINER"
for _ in $(seq 1 12); do
  CODE=$(curl -sSL -o /dev/null -w '%{http_code}' --max-time 30 "https://${FQDN}/" || true)
  [ "$CODE" = 200 ] && { echo "Cal.com recuperado: https://${FQDN}/ → redirect sano + 200"; exit 0; }
  sleep 5
done
fail "la app está healthy pero ${FQDN} no termina en 200"
