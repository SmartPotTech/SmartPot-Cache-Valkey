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
tcp-backlog 511
timeout 300
tcp-keepalive 60
databases ${DATABASES}
maxmemory ${MAXMEMORY}
maxmemory-policy allkeys-lru
save ""
appendonly no
dir /tmp
requirepass ${PASSWORD}
io-threads 4
io-threads-do-reads yes
activedefrag yes
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command CONFIG ""
rename-command DEBUG ""
rename-command SHUTDOWN ""
EOF

# Listener Dual Unix Domain Socket (UDS) si el directorio compartido o la variable VALKEY_SOCKET están disponibles
VALKEY_SOCKET_PATH="${VALKEY_SOCKET:-/var/run/smartpot/valkey.sock}"
SOCKET_DIR="$(dirname "$VALKEY_SOCKET_PATH")"
if [ -d "$SOCKET_DIR" ] && [ -w "$SOCKET_DIR" ]; then
  cat >> "$CONFIG" <<EOF
unixsocket ${VALKEY_SOCKET_PATH}
unixsocketperm 770
EOF
  echo "UDS habilitado: ${VALKEY_SOCKET_PATH} (perm 770)"
else
  echo "UDS no disponible o sin permisos en ${SOCKET_DIR}; operando exclusivamente en modo TCP 6379."
fi

# Carga en segundo plano de la librería de funciones Lua atómicas al arrancar el servicio
LUA_LIB="/usr/local/share/valkey/smartpot_functions.lua"
if [ -f "$LUA_LIB" ]; then
  (
    for _ in $(seq 1 40); do
      if REDISCLI_AUTH="$PASSWORD" valkey-cli -p 6379 ping 2>/dev/null | grep -q PONG; then
        REDISCLI_AUTH="$PASSWORD" valkey-cli -p 6379 FUNCTION LOAD REPLACE "$(cat "$LUA_LIB")" >/dev/null 2>&1 || true
        echo "Librería de funciones atómicas Lua (smartpot) precargada con éxito."
        break
      fi
      sleep 0.1
    done
  ) &
fi

echo "Valkey listo: ${MAXMEMORY} de memoria, multi-io 4 threads, sin persistencia y con contraseña."
exec valkey-server "$CONFIG"
