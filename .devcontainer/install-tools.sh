#!/bin/sh
# Shared install script for standalone CLI tools (dotenvx, task, uv, oc).
# Single source of truth for versions and checksums.
# Used by Docker multi-stage builds and devcontainer setup.
#
# Usage: sh install-tools.sh [--install-dir <dir>] <tool[@version]> [<tool[@version]>...]
# Available tools: dotenvx, task, uv, oc
# Example: sh install-tools.sh dotenvx task
# Example: sh install-tools.sh dotenvx@1.52.0 task@3.48.0
# Example: sh install-tools.sh --install-dir ~/.local/bin dotenvx task
set -eu

# Versions and SHA256 checksums keyed by <TOOL>_<VERSION_WITH_DOTS_AS_UNDERSCORES>_SHA256
DOTENVX_DEFAULT_VERSION="1.54.1"
DOTENVX_1_54_1_SHA256="0f5343c4467d0b9f4a770801bebc92625f2999e1ea2aa3548c5cb145a1b3ed3a"

TASK_DEFAULT_VERSION="3.49.1"
TASK_3_49_1_SHA256="4e7d24f1bf38218aec8f244eb7ba671f898830f9f87b3c9b30ff1c09e3135576"

UV_DEFAULT_VERSION="0.10.9"
UV_0_10_9_SHA256="20d79708222611fa540b5c9ed84f352bcd3937740e51aacc0f8b15b271c57594"

# Default to /usr/local/bin for production Docker builds
INSTALL_DIR="/usr/local/bin"

# Parse --install-dir flag if provided
if [ "${1:-}" = "--install-dir" ]; then
  shift
  INSTALL_DIR="${1}"
  shift
fi

# install_tool <url> <sha256> <binary_name> [<extra_binary>...]
# Downloads a tarball, verifies its checksum, and extracts named binaries.
install_tool() {
  url="$1" sha="$2"; shift 2
  first="$1"
  curl -fsSL "$url" -o "/tmp/${first}.tar.gz"
  echo "${sha}  /tmp/${first}.tar.gz" | sha256sum -c -
  mkdir -p "/tmp/${first}-extract"
  tar xzf "/tmp/${first}.tar.gz" -C "/tmp/${first}-extract"
  for bin in "$@"; do
    find "/tmp/${first}-extract" -name "$bin" -type f -exec mv {} "${INSTALL_DIR}/${bin}" \;
    chmod +x "${INSTALL_DIR}/${bin}"
  done
  rm -rf "/tmp/${first}.tar.gz" "/tmp/${first}-extract"
}

# lookup_sha <TOOL_UPPER> <version>
# Constructs the var name TOOL_X_Y_Z_SHA256 and prints its value, or exits if unknown.
lookup_sha() {
  tool_upper="$1" ver="$2"
  ver_key=$(echo "$ver" | tr '.' '_')
  sha_var="${tool_upper}_${ver_key}_SHA256"
  sha=$(eval echo "\${${sha_var}:-}")
  if [ -z "$sha" ]; then
    echo "No checksum registered for ${tool_upper}@${ver} (add ${sha_var} to the script)" >&2
    exit 1
  fi
  echo "$sha"
}

if [ $# -eq 0 ]; then
  echo "Usage: sh install-tools.sh [--install-dir <dir>] <tool[@version]> [<tool[@version]>...]" >&2
  echo "Available tools: dotenvx, task, uv, oc" >&2
  exit 1
fi

# Ensure install directory exists and expand ~ if present
INSTALL_DIR=$(eval echo "${INSTALL_DIR}")
mkdir -p "${INSTALL_DIR}"

for arg in "$@"; do
  tool="${arg%%@*}"
  if [ "$arg" != "$tool" ]; then
    version="${arg#*@}"
  else
    version=""
  fi

  case "$tool" in
    dotenvx)
      ver="${version:-$DOTENVX_DEFAULT_VERSION}"
      sha=$(lookup_sha "DOTENVX" "$ver")
      install_tool \
        "https://github.com/dotenvx/dotenvx/releases/download/v${ver}/dotenvx-linux-amd64.tar.gz" \
        "$sha" \
        "dotenvx"
      "${INSTALL_DIR}/dotenvx" --version
      ;;
    task)
      ver="${version:-$TASK_DEFAULT_VERSION}"
      sha=$(lookup_sha "TASK" "$ver")
      install_tool \
        "https://github.com/go-task/task/releases/download/v${ver}/task_linux_amd64.tar.gz" \
        "$sha" \
        "task"
      "${INSTALL_DIR}/task" --version
      ;;
    uv)
      ver="${version:-$UV_DEFAULT_VERSION}"
      sha=$(lookup_sha "UV" "$ver")
      install_tool \
        "https://github.com/astral-sh/uv/releases/download/${ver}/uv-x86_64-unknown-linux-gnu.tar.gz" \
        "$sha" \
        "uv"
      "${INSTALL_DIR}/uv" --version
      ;;
    *)
      echo "Unknown tool: $tool" >&2
      echo "Available tools: dotenvx, task, uv" >&2
      exit 1
      ;;
  esac
done
