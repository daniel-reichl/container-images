# Tools Image

Published `scratch` image of pinned CLI binaries for multi-stage `COPY --from=...` use in application Dockerfiles.

`ghcr.io/daniel-reichl/tools`

## Use It

```dockerfile
FROM ghcr.io/daniel-reichl/tools:latest AS tools

FROM debian:trixie-slim
COPY --from=tools /usr/local/bin/dotenvx /usr/local/bin/dotenvx
COPY --from=tools /usr/local/bin/task /usr/local/bin/task
```

## Binaries

- `caddy`
- `dotenvx`
- `task`
- `uv`
