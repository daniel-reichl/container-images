# container-images

This repository exists mainly to publish two reusable images:

- `ghcr.io/daniel-reichl/devcontainer` for opening projects in VS Code or other devcontainer-compatible tooling with a consistent toolchain.
- `ghcr.io/daniel-reichl/tools` for copying pinned CLI binaries such as `task` and `dotenvx` into production images.

The rest of the repo supports those two images: devcontainer templates, the local workspace devcontainer, a few minimal sample containers, and helper scripts.

## Layout

| Path | Purpose |
|------|---------|
| `package/devcontainer/` | Source for the published devcontainer image |
| `package/tools/` | Source for the published tools image |
| `templates/` | Ready-to-copy `.devcontainer` templates for other repositories |
| `containers/` | Minimal sample containers for testing infrastructure |
| `scripts/` | Docker install and cleanup helpers |
| `.devcontainer/` | Symlink to create local devcontainer for testing this repository |

## Quick Use

Use the published devcontainer image directly:

```jsonc
{
  "image": "ghcr.io/daniel-reichl/devcontainer:latest"
}
```

Use the published tools image in a multi-stage Docker build:

```dockerfile
FROM ghcr.io/daniel-reichl/tools:latest AS tools

FROM debian:bookworm-slim
COPY --from=tools /usr/local/bin/dotenvx /usr/local/bin/dotenvx
COPY --from=tools /usr/local/bin/task /usr/local/bin/task
```

## Templates

Both templates are Compose-based and mount the target repository at `/ws`.

- `templates/simple/` starts only the devcontainer service.
- `templates/with-db/` adds Postgres and runs `task install` after creation.

Copy either template into another repository's `.devcontainer/` directory and adjust it there.

## Sample Containers

The sample containers are intentionally small and OpenShift-friendly: they run as user `1001`, grant root-group access, and are useful for validating builds, ports, probes, and log collection before introducing application complexity.

- `containers/linux/` logs startup, counts down, and exits.
- `containers/node/` serves `/`, `/health`, and `/ready` on port `3000`.
- `containers/python/` serves the same endpoints on port `3000`.

## More Detail

- See [package/devcontainer/README.md](package/devcontainer/README.md) for the devcontainer image contents.
- See [package/tools/README.md](package/tools/README.md) for the tools image contents.
