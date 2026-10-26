#!/bin/sh
set -eu

# Valkey (reemplazo libre de Redis) acepta su propia variable VALKEY_PASSWORD y,
# por compatibilidad con despliegues anteriores, también REDIS_PASSWORD.
PASSWORD="${VALKEY_PASSWORD:-${REDIS_PASSWORD:-}}"
: "${PASSWORD:?Falta VALKEY_PASSWORD}"
if [ "${#PASSWORD}" -lt 16 ]; then
  echo "VALKEY_PASSWORD debe tener al menos 16 caracteres."
  exit 1
fi

MAXMEMORY="${VALKEY_MAXMEMORY:-${REDIS_MAXMEMORY:-128mb}}"
DATABASES="${VALKEY_DATABASES:-${REDIS_DATABASES:-4}}"

CONFIG="/tmp/valkey.conf"
umask 077
# Caché sin persistencia: lo que se pierda al reiniciar se reconstruye desde la API.
cat > "$CONFIG" <<EOF
bind 0.0.0.0
port 6379
protected-mode yes
databases ${DATABASES}
maxmemory ${MAXMEMORY}
maxmemory-policy allkeys-lru
save ""
appendonly no
dir /tmp
requirepass ${PASSWORD}
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
rename-command SHUTDOWN ""
EOF

echo "Valkey listo: ${MAXMEMORY} de memoria, sin persistencia y con contraseña."
exec valkey-server "$CONFIG"
