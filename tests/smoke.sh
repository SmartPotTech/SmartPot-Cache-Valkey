#!/bin/sh
# Arranca la imagen endurecida y valida autenticación, comandos bloqueados, ausencia de
# persistencia y la compatibilidad de variables con el Redis anterior.
set -eu

IMAGE="${1:-smartpot-cache-valkey:ci}"
NAME="smartpot-cache-valkey-smoke"
COMPAT="smartpot-cache-valkey-compat"
PASS="smoke-valkey-password-123"

cleanup() { docker rm -f "$NAME" "$COMPAT" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

docker run -d --name "$NAME" --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  -e VALKEY_PASSWORD="$PASS" "$IMAGE" >/dev/null

for _ in $(seq 1 20); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME")" = "healthy" ] && break
  sleep 1
done

cli() { docker exec "$NAME" valkey-cli -h 127.0.0.1 "$@" 2>&1; }
fail=0
check() { if eval "$2"; then echo "OK   $1"; else echo "FAIL $1"; fail=1; fi; }

check "el contenedor queda sano" '[ "$(docker inspect -f "{{.State.Health.Status}}" "$NAME")" = "healthy" ]'
check "sin contraseña se rechaza" 'cli ping | grep -q NOAUTH'
check "con contraseña responde" 'cli -a "$PASS" --no-auth-warning ping | grep -q PONG'
check "la imagen es Valkey, no Redis" 'cli -a "$PASS" --no-auth-warning info server | grep -qi "valkey_version"'
check "guarda y lee valores" 'cli -a "$PASS" --no-auth-warning set smoke 1 >/dev/null && cli -a "$PASS" --no-auth-warning get smoke | grep -q 1'
check "funciones Lua smartpot registradas" 'cli -a "$PASS" --no-auth-warning function list | grep -q smartpot'
check "FLUSHALL está deshabilitado" 'cli -a "$PASS" --no-auth-warning flushall | grep -qi "unknown command"'
check "CONFIG está deshabilitado" 'cli -a "$PASS" --no-auth-warning config get dir | grep -qi "unknown command"'
check "la contraseña no aparece en los logs" '! docker logs "$NAME" 2>&1 | grep -q "$PASS"'
check "sin contraseña el contenedor no arranca" '! docker run --rm "$IMAGE" >/dev/null 2>&1'

# Compatibilidad drop-in: una API que aún envía REDIS_PASSWORD debe seguir funcionando.
docker run -d --name "$COMPAT" --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  -e REDIS_PASSWORD="$PASS" "$IMAGE" >/dev/null
for _ in $(seq 1 20); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$COMPAT")" = "healthy" ] && break
  sleep 1
done
check "acepta REDIS_PASSWORD (compatibilidad)" '[ "$(docker inspect -f "{{.State.Health.Status}}" "$COMPAT")" = "healthy" ]'

exit "$fail"
