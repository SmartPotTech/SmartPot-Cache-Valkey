FROM valkey/valkey:9.1.2-alpine

LABEL org.opencontainers.image.title="SmartPot Cache (Valkey)" \
      org.opencontainers.image.description="Valkey de SmartPot: caché, contadores, UDS y funciones atómicas Lua, sin persistencia, con contraseña obligatoria" \
      org.opencontainers.image.source="https://github.com/SmartPotTech/SmartPot-Cache-Valkey" \
      org.opencontainers.image.licenses="MIT"

RUN mkdir -p /var/run/smartpot /usr/local/share/valkey /opt/smartpot/lua && \
    chown -R 999:1000 /var/run/smartpot /usr/local/share/valkey /opt/smartpot/lua

COPY --chmod=755 entrypoint.sh /usr/local/bin/smartpot-entrypoint.sh
COPY --chown=999:1000 lua/ /usr/local/share/valkey/
COPY --chown=999:1000 lua/ /opt/smartpot/lua/

USER 999:1000

EXPOSE 6379

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD REDISCLI_AUTH="${VALKEY_PASSWORD:-$REDIS_PASSWORD}" valkey-cli -h 127.0.0.1 ping | grep -q PONG || exit 1

ENTRYPOINT ["/usr/local/bin/smartpot-entrypoint.sh"]
