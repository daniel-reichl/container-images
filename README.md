# dev-container

Pre-built devcontainer image, templates, and Docker setup scripts.

## Overview

This repository contains three things:

1. **`.devcontainer/`** — A pre-built [dev container](https://containers.dev/) image published to GHCR (`ghcr.io/daniel-reichl/devcontainer`). It can be referenced from any external repository to provide a consistent, batteries-included development environment in VS Code, GitHub Codespaces, or any IDE that supports the dev containers spec.

2. **`templates/`** — Ready-to-copy `.devcontainer` configurations for consuming the pre-built image in another repository. Includes a simple (image-only) template and a Docker Compose template with a Postgres database.

3. **`scripts/`** — Shell scripts for installing Docker, configuring credential storage, and cleaning up unused containers and images.

## Repository Structure

```
.devcontainer/          # Dev container image definition
  Dockerfile            # Image build (Debian base + CLI tools)
  devcontainer.json     # Dev container spec (features, extensions, mounts)
  install-tools.sh      # Shared tool installer (dotenvx, task, uv)
  start-chrome.sh       # Headless Chrome launcher for GUI testing

.github/workflows/
  build.yaml            # CI — builds and pushes the devcontainer image to GHCR

templates/
  simple/
    devcontainer.json   # Image-only devcontainer config (no compose)
    docker-compose.yaml # Compose file for simple setup
  with-db/
    devcontainer.json   # Devcontainer config wired to docker-compose
    docker-compose.yaml # Compose file with app + Postgres service

scripts/
  install-docker.sh     # Install Docker Engine on Debian/Ubuntu (WSL2)
  setup-docker-pass.sh  # Configure docker-credential-pass with GPG
  cleanup-docker.sh     # Remove old containers and unused images
```

## Dev Container Image

The pre-built image is published to:

```
ghcr.io/daniel-reichl/devcontainer
```

To use it from another repository, add a `.devcontainer/devcontainer.json` that references the image:

```jsonc
{
  "image": "ghcr.io/daniel-reichl/devcontainer"
}
```

See the [.devcontainer README](.devcontainer/README.md) for details on what's included.

## Template

The [`templates/`](templates/) directory contains ready-to-use `.devcontainer` configurations that reference the pre-built image. To adopt one in another repository, copy the contents of the desired template into a `.devcontainer/` directory at the root of your project:

```bash
# Simple (image only, no database)
cp -r templates/simple/ <your-repo>/.devcontainer/

# With database (Docker Compose + Postgres)
cp -r templates/with-db/ <your-repo>/.devcontainer/
```

- **`simple/`** — References the image directly in `devcontainer.json`. Good for projects that don't need a database or other services.
- **`with-db/`** — Includes a `docker-compose.yaml` with the dev container service and a Postgres database, and a `devcontainer.json` wired up to use it. Adjust the services, volumes, and extensions to fit your project.

## Scripts

The [`scripts/`](scripts/) directory contains shell scripts for setting up and maintaining Docker on Debian/Ubuntu-based systems (including WSL2).

| Script | Description |
|--------|-------------|
| [`install-docker.sh`](scripts/install-docker.sh) | Installs Docker Engine from the official Docker repository (supports Debian and Ubuntu) |
| [`setup-docker-pass.sh`](scripts/setup-docker-pass.sh) | Configures `docker-credential-pass` with a GPG key for secure credential storage |
| [`cleanup-docker.sh`](scripts/cleanup-docker.sh) | Stops and removes containers and images not used in the last 7 days |
