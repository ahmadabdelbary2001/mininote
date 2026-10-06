#!/bin/bash
# Sets up multiarch (arm64) and installs cross-compilation target libraries
# on Ubuntu 24.04 (Noble) runners.
set -euo pipefail

echo "=== Configuring arm64 Multiarch & Target Libraries ==="

sudo dpkg --add-architecture arm64

# 1. Configure deb822 ubuntu.sources if present
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    if ! grep -q "Architectures:" /etc/apt/sources.list.d/ubuntu.sources; then
        sudo sed -i 's/Types: deb/Types: deb\nArchitectures: amd64/' /etc/apt/sources.list.d/ubuntu.sources
    fi
    cat << 'EOF' | sudo tee /etc/apt/sources.list.d/arm64-ports.sources
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble noble-updates noble-backports noble-security
Components: main universe restricted multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi

# 2. Configure legacy sources.list if present
if [ -f /etc/apt/sources.list ] && [ -s /etc/apt/sources.list ]; then
    sudo sed -i 's/^deb http/deb [arch=amd64] http/' /etc/apt/sources.list
    cat << 'EOF' | sudo tee /etc/apt/sources.list.d/arm64-ports.list
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ noble main universe restricted multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ noble-updates main universe restricted multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ noble-security main universe restricted multiverse
EOF
fi

echo "Updating APT package lists for arm64..."
sudo apt-get update

echo "Installing arm64 target libraries..."
sudo apt-get install -y --no-install-recommends \
    libxkbcommon-dev:arm64 \
    libwayland-dev:arm64 \
    libegl-dev:arm64 \
    libgles-dev:arm64 \
    libglib2.0-dev:arm64 \
    libmaliit-glib-dev:arm64

echo "=== arm64 Multiarch Setup Complete ==="
