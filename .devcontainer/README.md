# Dev Container

Pre-built development container image published to GHCR for use across repositories.

```
ghcr.io/daniel-reichl/devcontainer
```

## What's Included

### Base Image

Built on top of [`mcr.microsoft.com/devcontainers/base:debian`](https://github.com/devcontainers/images/tree/main/src/base-debian).

### Languages & Package Managers

| Tool | Version |
|------|---------|
| Node.js | 24 |
| pnpm | included |
| Python | 3.12 |
| uv | included |

### CLI Tools

| Tool | Description |
|------|-------------|
| `gh` | GitHub CLI |
| `oc` | OpenShift CLI |
| `kubectl` | Kubernetes CLI (bundled with `oc`) |
| `dotenvx` | Encrypted environment variable management |
| `task` | Task runner ([Taskfile](https://taskfile.dev)) |
| `claude` | Claude Code CLI |

### Browser

Chrome for Testing is installed via the [`chrometesting`](https://github.com/nickreemer/features/tree/main/src/chrometesting) dev container feature. A helper script (`start-chrome` / `chrome` alias) launches it with a clean profile, DevTools auto-open, and remote debugging on port 9222.

### VS Code Extensions

Automatically installed when the container is used in VS Code:

- GitHub Copilot Chat
- Biome (linter/formatter)
- dotenvx
- Git Graph
- Python Debugpy
- Toggle Excluded Files
- Open All Files

### GUI / Display Support

The container is configured to forward X11 and Wayland displays from the host (via WSLg mounts and environment variables), enabling GUI applications like Chrome to render natively.

## Usage

### From Another Repository

Reference the pre-built image in your project's `.devcontainer/devcontainer.json`:

```jsonc
{
  "image": "ghcr.io/daniel-reichl/devcontainer"
}
```

### In This Repository

Opening this repo in VS Code will automatically build and start the dev container from the local Dockerfile.

## CI / Build

The image is built and pushed to GHCR by the GitHub Actions workflow at [`.github/workflows/build.yaml`](../.github/workflows/build.yaml). It triggers on pushes to `main` that change files in `.devcontainer/` or `scripts/`, and can also be run manually via `workflow_dispatch`.

## Tool Versioning

Tool versions and SHA-256 checksums are pinned in [`install-tools.sh`](install-tools.sh). To update a tool, add the new version's checksum to the script and update the default version variable.
