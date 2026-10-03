#!/bin/bash
# End-to-end build script for MiniNotes on Ubuntu Touch.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

echo "=== Building MiniNotes for Ubuntu Touch (${ARCH}) ==="

case "$ARCH" in
    amd64)
        RUST_TARGET="x86_64-unknown-linux-gnu"
        LINKER="gcc"
        ;;
    arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        ;;
    armhf)
        RUST_TARGET="armv7-unknown-linux-gnueabihf"
        LINKER="arm-linux-gnueabihf-gcc"
        ;;
    *)
        echo "ERROR: Unsupported architecture $ARCH" >&2
        exit 1
        ;;
esac

# 1. Fetch matching Flutter engine artifacts
"$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH"

# 2. Build flutter-embedded-linux Wayland embedder
"$ROOT_DIR/scripts/build-embedder.sh" "$ARCH"

# 3. Build native_core (Rust cdylib)
echo "Building native_core ($RUST_TARGET)..."
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$ROOT_DIR/native_core/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# 4. Build mininote runner (Rust binary)
echo "Building mininote runner ($RUST_TARGET)..."
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$ROOT_DIR/flutter_app/elinux/runner/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# 5. Build Flutter bundle / assets
echo "Building Flutter assets..."
(
    cd "$ROOT_DIR/flutter_app"
    flutter pub get
    flutter build bundle --release
    mkdir -p "build/elinux/${ARCH}/release/bundle/data"
    cp -r "build/flutter_assets" "build/elinux/${ARCH}/release/bundle/data/"
)

# 6. Assemble and validate Click package
echo "Packaging Click..."
"$ROOT_DIR/scripts/package-click.sh" "$ARCH"

echo "=== MiniNotes build completed successfully for ${ARCH} ==="
