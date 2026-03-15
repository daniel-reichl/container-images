#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting Docker Engine installation script for Debian/Ubuntu-based WSL2..."
echo "This script will use 'sudo' and may prompt for your password."

echo ""
echo "Which base distribution are you using?"
echo "  1) Debian"
echo "  2) Ubuntu"
read -p "Enter 1 for Debian or 2 for Ubuntu [1/2]: " distro_choice

if [[ "$distro_choice" == "1" ]]; then
    DOCKER_URL_BASE="https://download.docker.com/linux/debian"
    DOCKER_GPG_URL="$DOCKER_URL_BASE/gpg"
    DISTRO_NAME="debian"
elif [[ "$distro_choice" == "2" ]]; then
    DOCKER_URL_BASE="https://download.docker.com/linux/ubuntu"
    DOCKER_GPG_URL="$DOCKER_URL_BASE/gpg"
    DISTRO_NAME="ubuntu"
else
    echo "Invalid choice. Please enter 1 for Debian or 2 for Ubuntu."
    exit 1
fi

# --- STEP 1: Update System Packages ---
echo ""
echo ">>> STEP 1: Updating package list..."
sudo apt-get update
# Optional: Uncomment the next two lines if you want to upgrade all packages as well
# echo ">>> STEP 1b: Upgrading existing packages..."
# sudo apt-get upgrade -y

# --- STEP 2: Install Prerequisites ---
echo ""
echo ">>> STEP 2: Installing prerequisite packages..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    gpg \
    lsb-release \
    pass

# --- STEP 3: Add Docker's official GPG key ---
echo ""
echo ">>> STEP 3: Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
if [ -f "/etc/apt/keyrings/docker.gpg" ]; then
    sudo rm /etc/apt/keyrings/docker.gpg
fi
curl -fsSL "$DOCKER_GPG_URL" | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# --- STEP 4: Set up the Docker repository ---
echo ""
echo ">>> STEP 4: Setting up the Docker APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_URL_BASE \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# --- STEP 5: Update package list with Docker repo ---
echo ""
echo ">>> STEP 5: Updating package list after adding Docker repo..."
sudo apt-get update

# --- STEP 6: Install Docker Engine, CLI, and containerd ---
echo ""
echo ">>> STEP 6: Installing Docker Engine, CLI, containerd, and plugins..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- STEP 7: Ensure docker group exists and add user ---
echo ""
echo ">>> STEP 7: Adding current user ($USER) to the 'docker' group..."
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi
sudo usermod -aG docker $USER

# --- STEP 8: Install Docker credential helper (docker-credential-pass) ---
echo ""
echo ">>> STEP 8: Installing Docker credential helper..."
CRED_HELPER_VERSION="0.8.2"
ARCH=$(dpkg --print-architecture)

# Map Debian arch names to the release binary naming convention
case "$ARCH" in
    amd64)  CRED_ARCH="amd64" ;;
    arm64)  CRED_ARCH="arm64" ;;
    armhf)  CRED_ARCH="armv6" ;;
    *)
        echo "WARNING: Unsupported architecture '$ARCH' for credential helper. Skipping."
        CRED_ARCH=""
        ;;
esac

if [ -n "$CRED_ARCH" ]; then
    CRED_HELPER_URL="https://github.com/docker/docker-credential-helpers/releases/download/v${CRED_HELPER_VERSION}/docker-credential-pass-v${CRED_HELPER_VERSION}.linux-${CRED_ARCH}"
    echo "Downloading docker-credential-pass v${CRED_HELPER_VERSION} for ${CRED_ARCH}..."
    curl -fsSL "$CRED_HELPER_URL" -o /tmp/docker-credential-pass
    chmod +x /tmp/docker-credential-pass
    sudo mv /tmp/docker-credential-pass /usr/local/bin/docker-credential-pass
    echo "docker-credential-pass installed to /usr/local/bin."
fi

# --- STEP 9: Set up GPG key and pass for Docker credential storage ---
echo ""
echo ">>> STEP 9: Configuring GPG and pass for Docker credential storage..."

# Check if a GPG key already exists for this user
EXISTING_KEY=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep "^sec" | awk '{print $2}' | cut -d'/' -f2 | head -n1)

if [ -n "$EXISTING_KEY" ]; then
    echo "Existing GPG key found: $EXISTING_KEY. Using it for pass."
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

# Initialize pass with the GPG key (safe to re-run if already initialized)
pass init "$GPG_KEY_ID"

# Configure Docker to use pass as its credential store
mkdir -p "$HOME/.docker"
DOCKER_CONFIG="$HOME/.docker/config.json"

if [ -f "$DOCKER_CONFIG" ]; then
    # Preserve existing config and add/update credsStore
    # Requires python3 (available on all modern Debian/Ubuntu)
    python3 -c "
import json, sys

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

# --- Display Final Instructions ---
echo ""
echo "------------------------------------------------------------"
echo "Docker installation script finished successfully!"
echo "------------------------------------------------------------"
echo ""
echo "NEXT STEPS:"
echo "--------------------"
echo "1.  Apply group membership changes for '$USER':"
echo "    You MUST close this WSL terminal completely"
echo "    and open a new one."
echo ""
echo "2.  Test Docker service:"
echo "    docker run hello-world"
echo ""
echo "NOTES:"
echo "--------------------"
echo "If necessary, the Docker service can be started with:"
echo "sudo service docker start"
echo ""
echo "Check status of the Docker service with:"
echo "sudo service docker status"
echo ""
echo "Your Docker credentials are now stored securely via 'pass'."
echo "GPG Key ID in use: $GPG_KEY_ID"
echo ""
echo "------------------------------------------------------------"
echo ""
exit 0
