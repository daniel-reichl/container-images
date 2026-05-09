#!/bin/sh
# Shared install script for standalone CLI tools.
# Single source of truth for versions and checksums.
# Used by Docker multi-stage builds and devcontainer setup.
#
# Usage: sh install-tools.sh [--install-dir <dir>] <tool[@version]> [<tool[@version]>...]
# Example: sh install-tools.sh dotenvx task
# Example: sh install-tools.sh dotenvx@1.52.0 task@3.48.0
# Example: sh install-tools.sh --install-dir ~/.local/bin dotenvx task
set -eu

###############################################################################
# 1) DEFINE TOOLS
###############################################################################

AVAILABLE_TOOLS="caddy dotenvx helm oc sqlcl task uv"

# Caddy (https://github.com/caddyserver/caddy/releases) [caddy_<ver>_linux_amd64.tar.gz]
CADDY_DEFAULT_VERSION="2.11.2"
CADDY_2_11_2="sha256:94391dfefe1f278ac8f387ab86162f0e88d87ff97df367f360e51e3cda3df56f"

# Dotenvx (https://github.com/dotenvx/dotenvx/releases) [dotenvx-linux-amd64.tar.gz]
DOTENVX_DEFAULT_VERSION="1.64.0"
DOTENVX_1_64_0="sha256:90c1c7f2575df047fadb6005a5c3fe6c599b086cc67e9c4def15af3537da71ba"

# OpenShift CLI (https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) [openshift-client-linux.tar.gz]
OC_DEFAULT_VERSION="4.21.12"
OC_4_21_12="sha256:9cc0f0de303bc21fb1cc8cb43e12f78aa2471e53547534c7335bc6bb25be4d6b"

# SQLcl (https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) [sqlcl-<ver>.zip]
SQLCL_DEFAULT_VERSION="26.1.0.086.1709"
SQLCL_26_1_0_086_1709="sha1:6467c611b081fa674f820d2393c1e48ebe431d15"

# Helm (https://github.com/helm/helm/releases) [helm-v<ver>-linux-amd64.tar.gz]
HELM_DEFAULT_VERSION="4.1.4"
HELM_4_1_4="sha256:70b2c30a19da4db264dfd68c8a3664e05093a361cefd89572ffb36f8abfa3d09"

# Task (https://github.com/go-task/task/releases) [task_linux_amd64.tar.gz]
TASK_DEFAULT_VERSION="3.50.0"
TASK_3_50_0="sha256:d449ba85ab85a0769989d78f8b9872938e4ba9347f7f4f925f73d98272a0a655"

# UV (https://github.com/astral-sh/uv/releases) [uv-x86_64-unknown-linux-gnu.tar.gz]
UV_DEFAULT_VERSION="0.11.8"
UV_0_11_8="sha256:56dd1b66701ecb62fe896abb919444e4b83c5e8645cca953e6ddd496ff8a0feb"

###############################################################################
# 2) UTILITY FUNCTIONS
###############################################################################

# lookup_checksum <TOOL_UPPER> <version>
# Constructs the var name TOOL_X_Y_Z and prints its algo:hash value, or exits if unknown.
lookup_checksum() {
  tool_upper="$1" ver="$2"
  ver_key=$(echo "$ver" | tr '.' '_')
  var="${tool_upper}_${ver_key}"
  checksum=$(eval echo "\${${var}:-}")
  if [ -z "$checksum" ]; then
    echo "No checksum registered for ${tool_upper}@${ver} (add ${var}=\"algo:hash\" to the script)" >&2
    exit 1
  fi
  echo "$checksum"
}

# verify_checksum <file> <algo:hash>
# Verifies a file against a prefixed checksum (e.g. sha256:abc... or sha1:abc...).
verify_checksum() {
  file="$1" checksum="$2"
  algo="${checksum%%:*}"
  hash="${checksum#*:}"
  case "$algo" in
    sha512) echo "${hash}  ${file}" | sha512sum -c - ;;
    sha256) echo "${hash}  ${file}" | sha256sum -c - ;;
    sha1)   echo "${hash}  ${file}" | sha1sum -c - ;;
    *)      echo "Unknown checksum algorithm: $algo" >&2; exit 1 ;;
  esac
}

# install_binary <url> <checksum> <binary_name>
# Downloads a standalone binary, verifies its checksum, and installs it.
install_binary() {
  url="$1" sha="$2" bin="$3"
  curl -fsSL "$url" -o "/tmp/${bin}"
  verify_checksum "/tmp/${bin}" "$sha"
  mv "/tmp/${bin}" "${INSTALL_DIR}/${bin}"
  chmod +x "${INSTALL_DIR}/${bin}"
}

# install_zip <url> <checksum> <dest_dir>
# Downloads a zip, verifies its checksum, and extracts to dest_dir.
install_zip() {
  url="$1" sha="$2" dest="$3"
  zip_file="/tmp/install_zip_$$.zip"
  curl -fsSL "$url" -o "$zip_file"
  verify_checksum "$zip_file" "$sha"
  unzip -q "$zip_file" -d "$dest"
  rm -f "$zip_file"
}

# install_tar <url> <checksum> <binary_name> [<extra_binary>...]
# Downloads a tarball, verifies its checksum, and extracts named binaries.
install_tar() {
  url="$1" sha="$2"; shift 2
  first="$1"
  curl -fsSL "$url" -o "/tmp/${first}.tar.gz"
  verify_checksum "/tmp/${first}.tar.gz" "$sha"
  mkdir -p "/tmp/${first}-extract"
  tar xzf "/tmp/${first}.tar.gz" -C "/tmp/${first}-extract"
  for bin in "$@"; do
    find "/tmp/${first}-extract" -name "$bin" -type f -exec mv {} "${INSTALL_DIR}/${bin}" \;
    chmod +x "${INSTALL_DIR}/${bin}"
  done
  rm -rf "/tmp/${first}.tar.gz" "/tmp/${first}-extract"
}

###############################################################################
# 3) MAIN SCRIPT
###############################################################################

# Default to /usr/local/bin for production Docker builds
INSTALL_DIR="/usr/local/bin"

# Parse --install-dir flag if provided
if [ "${1:-}" = "--install-dir" ]; then
  shift
  INSTALL_DIR="${1}"
  shift
fi

if [ $# -eq 0 ]; then
  echo "Usage: sh install-tools.sh [--install-dir <dir>] <tool[@version]> [<tool[@version]>...]" >&2
  echo "Available tools: ${AVAILABLE_TOOLS}" >&2
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
    caddy)
      ver="${version:-$CADDY_DEFAULT_VERSION}"
      sha=$(lookup_checksum "CADDY" "$ver")
      install_tar \
        "https://github.com/caddyserver/caddy/releases/download/v${ver}/caddy_${ver}_linux_amd64.tar.gz" \
        "$sha" \
        "caddy"
      "${INSTALL_DIR}/caddy" version
      ;;
    dotenvx)
      ver="${version:-$DOTENVX_DEFAULT_VERSION}"
      sha=$(lookup_checksum "DOTENVX" "$ver")
      install_tar \
        "https://github.com/dotenvx/dotenvx/releases/download/v${ver}/dotenvx-linux-amd64.tar.gz" \
        "$sha" \
        "dotenvx"
      "${INSTALL_DIR}/dotenvx" --version
      ;;
    helm)
      ver="${version:-$HELM_DEFAULT_VERSION}"
      sha=$(lookup_checksum "HELM" "$ver")
      install_tar \
        "https://get.helm.sh/helm-v${ver}-linux-amd64.tar.gz" \
        "$sha" \
        "helm"
      "${INSTALL_DIR}/helm" version
      ;;
    task)
      ver="${version:-$TASK_DEFAULT_VERSION}"
      sha=$(lookup_checksum "TASK" "$ver")
      install_tar \
        "https://github.com/go-task/task/releases/download/v${ver}/task_linux_amd64.tar.gz" \
        "$sha" \
        "task"
      "${INSTALL_DIR}/task" --version
      ;;
    uv)
      ver="${version:-$UV_DEFAULT_VERSION}"
      sha=$(lookup_checksum "UV" "$ver")
      install_tar \
        "https://github.com/astral-sh/uv/releases/download/${ver}/uv-x86_64-unknown-linux-gnu.tar.gz" \
        "$sha" \
        "uv"
      "${INSTALL_DIR}/uv" --version
      ;;
    oc)
      ver="${version:-$OC_DEFAULT_VERSION}"
      sha=$(lookup_checksum "OC" "$ver")
      install_tar \
        "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${ver}/openshift-client-linux.tar.gz" \
        "$sha" \
        oc kubectl
      "${INSTALL_DIR}/oc" version --client
      ;;
    sqlcl)
      ver="${version:-$SQLCL_DEFAULT_VERSION}"
      sha=$(lookup_checksum "SQLCL" "$ver")
      install_zip \
        "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-${ver}.zip" \
        "$sha" \
        /opt/oracle
      chmod +x /opt/oracle/sqlcl/bin/sql
      chmod -R o+r /opt/oracle/sqlcl/lib
      /opt/oracle/sqlcl/bin/sql -V
      ;;
    *)
      echo "Unknown tool: $tool" >&2
      echo "Available tools: ${AVAILABLE_TOOLS}" >&2
      exit 1
      ;;
  esac
done
