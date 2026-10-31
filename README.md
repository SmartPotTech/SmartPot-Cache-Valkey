# SmartPot-Cache-Valkey

## Estado del Proyecto

[![Cache Image CI](https://github.com/SmartPotTech/SmartPot-Cache-Valkey/actions/workflows/ci.yml/badge.svg)](https://github.com/SmartPotTech/SmartPot-Cache-Valkey/actions/workflows/ci.yml)
[![Publish Docker Images](https://github.com/SmartPotTech/SmartPot-Cache-Valkey/actions/workflows/packaging.yml/badge.svg)](https://github.com/SmartPotTech/SmartPot-Cache-Valkey/actions/workflows/packaging.yml)

## Descripción

SmartPot-Cache-Valkey es la caché de SmartPot sobre **[Valkey](https://valkey.io/)**, el derivado libre de Redis
mantenido por la Linux Foundation bajo licencia **BSD-3-Clause**. Sustituye a [SmartPot-Cache](https://github.com/SmartPotTech/SmartPot-Cache)
(Redis), que desde la versión 8 dejó de ser software libre y pasó a una licencia restringida. Valkey habla el mismo
protocolo (RESP) y los mismos comandos, así que para la [API en Go](https://github.com/SmartPotTech/SmartPot-API-Go) el
cambio es **transparente**: la misma dirección, la misma contraseña y el mismo cliente.

La API la usa para datos cortos y compartidos entre peticiones:

| Uso                                              | Llaves                                                        | Vida                                    |
|--------------------------------------------------|---------------------------------------------------------------|-----------------------------------------|
| Límite de peticiones por IP                      | `smartpot:rate:*`                                             | 1 minuto                                |
| Frecuencia mínima de telemetría por cultivo      | `smartpot:reading:*`                                          | 5 segundos                              |
| Enfriamiento del agente y de las alertas         | `smartpot:agent:*`, `smartpot:notify:*`, `smartpot:ai-eval:*` | Minutos u horas                         |
| Perfiles de cultivo del servicio de IA           | `smartpot:ai:crop-profiles`                                   | 1 hora                                  |
| Resumen de lo aprendido por la IA                | `smartpot:ai:learning-status`                                 | 1 minuto                                |
| Códigos de un solo uso para vincular Telegram    | `smartpot:channel-link:telegram:*`                            | 10 minutos (se borran al usarse)        |
| Enlaces de un solo uso para compartir un cultivo | `smartpot:crop-share:telegram:*`                              | 10 minutos (se borran al usarse)        |
| Clima del lugar de cada cultivo                  | `smartpot:weather:{lat}:{lon}`                                | 10 minutos (2 si el clima no respondió) |

Es una caché **sin persistencia**: si se reinicia, la API reconstruye todo. Si Valkey no responde, la API sigue
funcionando con memoria local durante 30 segundos y vuelve a intentar.

## Por qué Valkey

- **Licencia libre.** Valkey mantiene la licencia BSD-3-Clause con la que Redis era de código abierto; Redis 8 es ahora
  software con fuente disponible pero bajo licencia restringida (AGPLv3 / SSPLv2 / RSALv2).
- **Reemplazo directo.** Mismo protocolo, mismos comandos, mismo puerto 6379 y la misma configuración
  (`requirepass`, `maxmemory`, `rename-command`…). No cambia ningún contrato ni la forma en que la API la consulta.
- **Compatibilidad de variables.** La imagen acepta `VALKEY_PASSWORD` y, si solo existe `REDIS_PASSWORD`, también la
  usa, para que ningún despliegue existente se rompa durante el corte.

## Seguridad

- Contraseña obligatoria de al menos 16 caracteres (`VALKEY_PASSWORD`, o `REDIS_PASSWORD` por compatibilidad); sin ella
  el contenedor no arranca.
- La configuración se genera en `/tmp` al arrancar y nunca se imprime en los logs.
- `FLUSHALL`, `FLUSHDB`, `CONFIG`, `DEBUG` y `SHUTDOWN` están deshabilitados.
- Corre como el usuario `999`, con sistema de archivos de solo lectura y sin capacidades de Linux.
- En producción no publica puertos: solo la API lo alcanza por la red interna de Docker.

## Estructura del Proyecto

```text
SmartPot-Cache-Valkey/
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml              # Construye la imagen y corre la prueba de seguridad
│       ├── packaging.yml       # Publica la imagen en GHCR con SBOM y procedencia (y en Docker Hub con credenciales)
│       └── deploy.yml          # Pide el despliegue al workflow central de SmartPotTech/.github
├── tests/
│   └── smoke.sh                # Autenticación, comandos bloqueados, logs sin secretos y compatibilidad de variables
├── compose.yaml
├── Dockerfile                  # valkey/valkey:9.1.2-alpine sin privilegios
├── entrypoint.sh               # Genera la configuración con la contraseña del entorno
└── .env.example
```

## Guía de Instalación

```bash
git clone https://github.com/SmartPotTech/SmartPot-Cache-Valkey.git
cd SmartPot-Cache-Valkey
cp .env.example .env    # define VALKEY_PASSWORD
docker compose up -d
```

| Variable           | Por defecto | Descripción                                                |
|--------------------|-------------|------------------------------------------------------------|
| `VALKEY_PASSWORD`  | —           | Obligatoria, mínimo 16 caracteres (acepta `REDIS_PASSWORD`) |
| `VALKEY_MAXMEMORY` | `128mb`     | Memoria máxima; se descartan las llaves menos usadas (LRU) |
| `VALKEY_DATABASES` | `4`         | Bases lógicas disponibles                                  |

### Prueba de humo

```bash
docker build -t smartpot-cache-valkey:ci .
sh tests/smoke.sh smartpot-cache-valkey:ci
```

## Imagen publicada

```bash
docker pull ghcr.io/smartpottech/smartpot-cache-valkey:latest
```

Cada cambio en `main` pasa por el CI, publica la imagen en GHCR (y en Docker Hub como réplica cuando el repositorio
tiene credenciales) y pide el despliegue al workflow central
de [SmartPotTech/.github](https://github.com/SmartPotTech/.github), que actualiza producción de a uno y verifica
`/health`.

## Documentación

Valkey guarda solo datos efímeros: si se pierde, la plataforma sigue. Su documentación propia está en [
`docs/`](docs/SmartPot_Cache_Documentation.md), con sus diagramas en [`docs/diagrams`](docs/diagrams): el general de la
imagen y el de las llaves.
La [documentación técnica](https://github.com/SmartPotTech/.github/blob/main/docs/SmartPot_Technical_Documentation.md)
explica para qué usa la API cada llave y cómo actúa si la caché no responde. Los diagramas generales muestran la
plataforma completa en una sola imagen ampliable:

- [Arquitectura completa](https://github.com/SmartPotTech/.github/blob/main/docs/diagrams/SmartPot_Global_01_Architecture.svg):
  dónde vive la caché y qué llaves guarda
- [Linaje de los datos](https://github.com/SmartPotTech/.github/blob/main/docs/diagrams/SmartPot_Global_04_Data_Lineage.svg):
  en qué momento de cada flujo se consulta o se escribe una llave

## Hoja de Ruta Industrial: Multi-IO, Transporte UDS y Funciones Lua Atómicas

Como parte del **Plan Maestro de Maximización del Stack B (demo-beta)**, `SmartPot-Cache-Valkey` incorpora afinaciones de rendimiento extremo:

1. **Listener Dual (UDS y TCP)**:
   - Configuración de socket UNIX `/var/run/smartpot/valkey.sock` con permisos 770 para comunicación sin sobrecarga TCP en despliegues mononodo (`demo-beta`), preservando el puerto TCP 6379 para escalado en red.
2. **Concurrencia Multi-Hilo y Memoria**:
   - `io-threads 4` e `io-threads-do-reads yes` para paralelizar la lectura y escritura de sockets.
   - Activación de purga asíncrona de Jemalloc (`lazyfree-lazy-eviction yes`, `lazyfree-lazy-expire yes`, `activedefrag yes`).
3. **Funciones Lua Atómicas (`FUNCTION LOAD`)**:
   - Evaluación atómica de umbrales del filtro de banda muerta agronómico.
   - Deduplicación de paquetes MQTT por `sequence_id`.
   - Algoritmo de tasa Generic Cell Rate Algorithm (GCRA) evaluado en una única transacción.

## Licencia

Este proyecto está bajo la licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles. La imagen base
[Valkey](https://github.com/valkey-io/valkey) se distribuye bajo BSD-3-Clause.
