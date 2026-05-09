# ============================================================
# Tools Image — Pre-built, checksum-verified CLI binaries
# ============================================================
# Provides: caddy, dotenvx, task, uv
# Usage in production Dockerfiles:
#   FROM ghcr.io/hrda-dev/tools:<tag> AS tools
#   COPY --from=tools /usr/local/bin/dotenvx /usr/local/bin/dotenvx
# ============================================================
FROM debian:trixie-slim AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package/devcontainer/install-tools.sh /tmp/install-tools.sh
RUN sh /tmp/install-tools.sh caddy dotenvx task uv

FROM scratch
LABEL org.opencontainers.image.description="Scratch-based tools image with pinned caddy, dotenvx, task, and uv binaries for multi-stage Docker builds"

COPY --from=builder /usr/local/bin/caddy /usr/local/bin/caddy
COPY --from=builder /usr/local/bin/dotenvx /usr/local/bin/dotenvx
COPY --from=builder /usr/local/bin/task /usr/local/bin/task
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv
