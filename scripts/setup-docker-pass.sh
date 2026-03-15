#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting Docker credential helper setup..."
echo "This script will use 'sudo' and may prompt for your password."

# --- STEP 1: Install dependencies ---
echo ""
echo ">>> STEP 1: Installing gpg and pass..."
sudo apt-get update -q
sudo apt-get install -y gpg pass

# --- STEP 2: Install docker-credential-pass ---
echo ""
echo ">>> STEP 2: Installing docker-credential-pass..."
CRED_HELPER_VERSION="0.8.2"
ARCH=$(dpkg --print-architecture)

case "$ARCH" in
    amd64)  CRED_ARCH="amd64" ;;
    arm64)  CRED_ARCH="arm64" ;;
    armhf)  CRED_ARCH="armv6" ;;
    *)
        echo "ERROR: Unsupported architecture '$ARCH'. Exiting."
        exit 1
        ;;
esac

CRED_HELPER_URL="https://github.com/docker/docker-credential-helpers/releases/download/v${CRED_HELPER_VERSION}/docker-credential-pass-v${CRED_HELPER_VERSION}.linux-${CRED_ARCH}"
echo "Downloading docker-credential-pass v${CRED_HELPER_VERSION} for ${CRED_ARCH}..."
curl -fsSL "$CRED_HELPER_URL" -o /tmp/docker-credential-pass
chmod +x /tmp/docker-credential-pass
sudo mv /tmp/docker-credential-pass /usr/local/bin/docker-credential-pass
echo "docker-credential-pass installed to /usr/local/bin."

# --- STEP 3: Set up GPG key ---
echo ""
echo ">>> STEP 3: Checking for existing GPG key..."
EXISTING_KEY=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "^sec" | awk '{print $2}' | cut -d'/' -f2 | head -n1)

if [ -n "$EXISTING_KEY" ]; then
    echo "Existing GPG key found: $EXISTING_KEY. Using it."
    GPG_KEY_ID="$EXISTING_KEY"
else
    echo "No GPG key found. Generating a new one..."
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Docker Credentials
Name-Email: docker@localhost
Expire-Date: 0
EOF
    GPG_KEY_ID=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "^sec" | awk '{print $2}' | cut -d'/' -f2 | head -n1)
    echo "New GPG key generated: $GPG_KEY_ID"
fi

# --- STEP 4: Initialize pass ---
echo ""
echo ">>> STEP 4: Initializing pass with GPG key $GPG_KEY_ID..."
pass init "$GPG_KEY_ID"

# --- STEP 5: Configure Docker to use pass ---
echo ""
echo ">>> STEP 5: Configuring Docker to use pass as credential store..."
mkdir -p "$HOME/.docker"
DOCKER_CONFIG="$HOME/.docker/config.json"

if [ -f "$DOCKER_CONFIG" ]; then
    python3 -c "
import json

with open('$DOCKER_CONFIG', 'r') as f:
    config = json.load(f)

config['credsStore'] = 'pass'

with open('$DOCKER_CONFIG', 'w') as f:
    json.dump(config, f, indent=2)

print('Updated existing $DOCKER_CONFIG with credsStore=pass')
"
else
    echo '{ "credsStore": "pass" }' > "$DOCKER_CONFIG"
    echo "Created $DOCKER_CONFIG with credsStore=pass"
fi

echo ""
echo "------------------------------------------------------------"
echo "Docker credential helper setup complete!"
echo "GPG Key ID in use: $GPG_KEY_ID"
echo ""
echo "You can now run 'docker login' and your credentials"
echo "will be stored securely via pass."
echo "------------------------------------------------------------"
echo ""
exit 0
