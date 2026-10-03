#!/bin/bash
# End-to-end build script for MiniNotes on Ubuntu Touch.
# Phase 2: Includes proper AOT compilation (libapp.so) and icudtl.dat placement.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

echo "=== Building MiniNotes for Ubuntu Touch (${ARCH}) ==="

case "$ARCH" in
    amd64)
        RUST_TARGET="x86_64-unknown-linux-gnu"
        LINKER="gcc"
        FLUTTER_TARGET="linux-x64"
        GEN_SNAPSHOT_PLATFORM="linux-x64"
        ;;
    arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        FLUTTER_TARGET="linux-arm64"
        GEN_SNAPSHOT_PLATFORM="linux-arm64"
        ;;
    armhf)
        RUST_TARGET="armv7-unknown-linux-gnueabihf"
        LINKER="arm-linux-gnueabihf-gcc"
        FLUTTER_TARGET="linux-arm"
        GEN_SNAPSHOT_PLATFORM="linux-x64"   # gen_snapshot is always host arch
        ;;
    *)
        echo "ERROR: Unsupported architecture $ARCH" >&2
        exit 1
        ;;
esac

# ─── 1. Fetch matching Flutter engine artifacts ────────────────────────────
"$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"

# ─── 2. Build flutter-embedded-linux Wayland embedder ─────────────────────
"$ROOT_DIR/scripts/build-embedder.sh" "$ARCH"

# ─── 3. Build native_core (Rust cdylib) ───────────────────────────────────
echo "Building native_core ($RUST_TARGET)..."
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$ROOT_DIR/native_core/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# ─── 4. Build mininote runner (Rust binary) ───────────────────────────────
echo "Building mininote runner ($RUST_TARGET)..."
# Pass engine/embedder library search paths so build.rs linkage check passes
FLUTTER_ENGINE_LIB_DIR="$ENGINE_DIR" \
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$ROOT_DIR/flutter_app/elinux/runner/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# ─── 5. Build Flutter Dart kernel snapshot ────────────────────────────────
echo "Building Flutter assets / kernel snapshot..."
(
    cd "$ROOT_DIR/flutter_app"
    flutter pub get
    # flutter build bundle produces kernel_blob.bin + assets; no native code yet
    flutter build bundle --release
)

FLUTTER_BUILD_DIR="$ROOT_DIR/flutter_app/build"

# ─── 6. AOT: compile Dart → libapp.so via gen_snapshot ───────────────────
# We resolve gen_snapshot from the Flutter SDK (always a host-arch binary).
FLUTTER_BIN="$(which flutter)"
FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"

# engine.version file gives the exact hash used by this SDK
ENGINE_SHA_FILE="$FLUTTER_ROOT/bin/internal/engine.version"
ENGINE_SHA=""
if [ -f "$ENGINE_SHA_FILE" ]; then
    ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_SHA_FILE")"
fi

GEN_SNAPSHOT=""
# Try pre-cached gen_snapshot from the engine artifact
GEN_SNAPSHOT_CANDIDATES=(
    "$ENGINE_DIR/gen_snapshot"
    "$FLUTTER_ROOT/bin/cache/artifacts/engine/${GEN_SNAPSHOT_PLATFORM}/gen_snapshot"
    "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/gen_snapshot"
)
for candidate in "${GEN_SNAPSHOT_CANDIDATES[@]}"; do
    if [ -x "$candidate" ]; then
        GEN_SNAPSHOT="$candidate"
        break
    fi
done

if [ -z "$GEN_SNAPSHOT" ] && [ -n "$ENGINE_SHA" ]; then
    echo "Fetching gen_snapshot from Flutter infrastructure..."
    GEN_SNAP_ZIP_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}/${GEN_SNAPSHOT_PLATFORM}/linux-x64-${GEN_SNAPSHOT_PLATFORM}.zip"
    TMP_GEN="$(mktemp -d)"
    if curl -sSLf "$GEN_SNAP_ZIP_URL" -o "$TMP_GEN/gs.zip"; then
        unzip -q -o "$TMP_GEN/gs.zip" -d "$TMP_GEN"
        if [ -f "$TMP_GEN/gen_snapshot" ]; then
            chmod +x "$TMP_GEN/gen_snapshot"
            GEN_SNAPSHOT="$TMP_GEN/gen_snapshot"
        fi
    fi
fi

# Determine cross-compile ELF triplet flags for gen_snapshot
GEN_SNAPSHOT_ARCH_FLAGS=""
case "$ARCH" in
    arm64) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so --no-sim-use-hardfp" ;;
    armhf) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so --sim-use-hardfp" ;;
    amd64) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so" ;;
esac

KERNEL_SNAPSHOT="$FLUTTER_BUILD_DIR/flutter_assets/kernel_blob.bin"
LIB_DIR="$FLUTTER_BUILD_DIR/elinux/${ARCH}/release/bundle/lib"
mkdir -p "$LIB_DIR"

if [ -n "$GEN_SNAPSHOT" ] && [ -f "$KERNEL_SNAPSHOT" ]; then
    echo "Running gen_snapshot (AOT) for $ARCH → libapp.so ..."
    (
        cd "$LIB_DIR"
        # shellcheck disable=SC2086
        "$GEN_SNAPSHOT" $GEN_SNAPSHOT_ARCH_FLAGS "$KERNEL_SNAPSHOT"
    )
    echo "  [OK] libapp.so generated at $LIB_DIR/libapp.so"
else
    echo "WARNING: gen_snapshot not available or kernel_blob.bin missing;"
    echo "         Falling back to JIT (debug only — do NOT ship this)."
fi

# ─── 7. Assemble bundle structure ─────────────────────────────────────────
BUNDLE_OUT="$FLUTTER_BUILD_DIR/elinux/${ARCH}/release/bundle"
mkdir -p "$BUNDLE_OUT/data"

# Copy flutter_assets into bundle
if [ -d "$FLUTTER_BUILD_DIR/flutter_assets" ]; then
    cp -r "$FLUTTER_BUILD_DIR/flutter_assets" "$BUNDLE_OUT/data/"
fi

# Copy icudtl.dat (required by Flutter engine at startup)
if [ -f "$ENGINE_DIR/icudtl.dat" ]; then
    cp "$ENGINE_DIR/icudtl.dat" "$BUNDLE_OUT/data/icudtl.dat"
    echo "  [OK] icudtl.dat copied to bundle"
else
    echo "WARNING: icudtl.dat not found in $ENGINE_DIR — engine may fail to start."
fi

# ─── 8. Assemble and validate Click package ───────────────────────────────
echo "Packaging Click..."
"$ROOT_DIR/scripts/package-click.sh" "$ARCH"

echo "=== MiniNotes build completed successfully for ${ARCH} ==="
