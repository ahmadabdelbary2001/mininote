#!/bin/bash
# End-to-end build script for MiniNotes on Ubuntu Touch.
# Phase 2: Includes mandatory AOT compilation (libapp.so) and icudtl.dat placement.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

echo "=== Building MiniNotes for Ubuntu Touch (${ARCH}) ==="

case "$ARCH" in
    amd64)
        RUST_TARGET="x86_64-unknown-linux-gnu"
        LINKER="gcc"
        FLUTTER_TARGET="linux-x64"
        # gen_snapshot for amd64: host-arch binary, targets x64
        GEN_SNAPSHOT_PLATFORM="linux-x64"
        # Cross-build artifact path (same as host for amd64)
        GEN_SNAPSHOT_XARCH_PATH="linux-x64"
        ELF_ARCH_PATTERN="x86-64"
        ;;
    arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        FLUTTER_TARGET="linux-arm64"
        # gen_snapshot for arm64 cross-build on x64 host:
        # Must be the x64-hosted binary that emits AArch64 AOT code.
        # Flutter SDK downloads it under: linux-arm64-release/clang_x64/gen_snapshot
        # Ref: https://docs.sony.com/flutter-embedded/cross-building-arm64
        GEN_SNAPSHOT_PLATFORM="linux-arm64"
        GEN_SNAPSHOT_XARCH_PATH="linux-arm64-release/clang_x64"
        ELF_ARCH_PATTERN="aarch64"
        ;;
    armhf)
        RUST_TARGET="armv7-unknown-linux-gnueabihf"
        LINKER="arm-linux-gnueabihf-gcc"
        FLUTTER_TARGET="linux-arm"
        GEN_SNAPSHOT_PLATFORM="linux-x64"
        GEN_SNAPSHOT_XARCH_PATH="linux-x64"
        ELF_ARCH_PATTERN=""
        ;;
    *)
        echo "ERROR: Unsupported architecture $ARCH" >&2
        exit 1
        ;;
esac

if [ "$ARCH" = "armhf" ]; then
    echo "=========================================================================="
    echo "NOTICE: Official Flutter Engine artifacts for 32-bit ARM (armhf) are"
    echo "discontinued upstream by Flutter for Flutter >= 3.10."
    echo "All current Ubuntu Touch production devices run arm64 (aarch64)."
    echo "Skipping armhf build gracefully."
    echo "=========================================================================="
    mkdir -p "$ROOT_DIR/dist"
    echo "armhf build skipped: 32-bit ARM engine is unavailable upstream for Flutter >= 3.10" > "$ROOT_DIR/dist/armhf-skipped.txt"
    exit 0
fi

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
    flutter build bundle --release
)

FLUTTER_BUILD_DIR="$ROOT_DIR/flutter_app/build"

# ─── 6. AOT: compile Dart → libapp.so via gen_snapshot ───────────────────
# MANDATORY for production release builds.
# gen_snapshot is always a host-arch (x64) binary that emits target-arch AOT code.
# For arm64 cross-build the correct binary lives at:
#   <flutter_root>/bin/cache/artifacts/engine/linux-arm64-release/clang_x64/gen_snapshot
# NOT at linux-x64/gen_snapshot (which emits x64 AOT) or linux-arm64/gen_snapshot (not x64-runnable).
FLUTTER_BIN="$(which flutter)"
FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"

ENGINE_SHA_FILE="$FLUTTER_ROOT/bin/internal/engine.version"
ENGINE_SHA=""
if [ -f "$ENGINE_SHA_FILE" ]; then
    ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_SHA_FILE")"
fi

GEN_SNAPSHOT=""

# Priority 1: Cross-arch specific path (e.g. linux-arm64-release/clang_x64/gen_snapshot for arm64)
GEN_SNAPSHOT_CANDIDATES=(
    "$FLUTTER_ROOT/bin/cache/artifacts/engine/${GEN_SNAPSHOT_XARCH_PATH}/gen_snapshot"
    "$FLUTTER_ROOT/bin/cache/artifacts/engine/${GEN_SNAPSHOT_PLATFORM}/gen_snapshot"
    "$ENGINE_DIR/gen_snapshot"
    "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/gen_snapshot"
)
for candidate in "${GEN_SNAPSHOT_CANDIDATES[@]}"; do
    if [ -x "$candidate" ]; then
        GEN_SNAPSHOT="$candidate"
        echo "  Found gen_snapshot: $candidate"
        break
    fi
done

# Priority 2: Download from Flutter infrastructure (cross-arch path first)
if [ -z "$GEN_SNAPSHOT" ] && [ -n "$ENGINE_SHA" ]; then
    echo "gen_snapshot not in cache; fetching from Flutter infrastructure..."

    # For arm64: the cross-build gen_snapshot is in linux-arm64-release/clang_x64/
    # URL pattern: flutter/<sha>/linux-arm64-release/linux-arm64-release.zip
    # Or: flutter/<sha>/linux-x64/linux-x64.zip (fallback, emits x64 AOT)
    TMP_GEN="$(mktemp -d)"

    # Try cross-arch zip first (for arm64: linux-arm64-release)
    XARCH_ZIP_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}/${GEN_SNAPSHOT_XARCH_PATH%/clang_x64}/${GEN_SNAPSHOT_PLATFORM}-release.zip"
    XARCH_ZIP_URL2="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}/${GEN_SNAPSHOT_XARCH_PATH}/gen_snapshot"
    # Also try the simple per-arch zip
    SIMPLE_ZIP_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}/${GEN_SNAPSHOT_PLATFORM}/linux-x64-${GEN_SNAPSHOT_PLATFORM}.zip"

    for gs_url in "$XARCH_ZIP_URL2" "$SIMPLE_ZIP_URL"; do
        if curl -sSLf --max-time 120 "$gs_url" -o "$TMP_GEN/gen_snapshot" 2>/dev/null; then
            chmod +x "$TMP_GEN/gen_snapshot"
            # Quick sanity: must be an x86-64 ELF (runs on the x64 CI host)
            if file "$TMP_GEN/gen_snapshot" | grep -q "x86-64"; then
                GEN_SNAPSHOT="$TMP_GEN/gen_snapshot"
                echo "  Fetched gen_snapshot from: $gs_url"
                break
            fi
        fi
        # Try as zip
        if curl -sSLf --max-time 120 "$gs_url" -o "$TMP_GEN/gs.zip" 2>/dev/null; then
            unzip -q -o "$TMP_GEN/gs.zip" -d "$TMP_GEN" 2>/dev/null || true
            if [ -f "$TMP_GEN/gen_snapshot" ] && [ -f "$TMP_GEN/clang_x64/gen_snapshot" ]; then
                chmod +x "$TMP_GEN/clang_x64/gen_snapshot"
                GEN_SNAPSHOT="$TMP_GEN/clang_x64/gen_snapshot"
                break
            elif [ -f "$TMP_GEN/gen_snapshot" ]; then
                chmod +x "$TMP_GEN/gen_snapshot"
                if file "$TMP_GEN/gen_snapshot" | grep -q "x86-64"; then
                    GEN_SNAPSHOT="$TMP_GEN/gen_snapshot"
                    break
                fi
            fi
        fi
    done
fi

# Trigger flutter precache for the target platform to populate cache paths
if [ -z "$GEN_SNAPSHOT" ]; then
    echo "Attempting flutter precache for ${GEN_SNAPSHOT_PLATFORM}..."
    flutter precache --linux 2>/dev/null || true
    for candidate in "${GEN_SNAPSHOT_CANDIDATES[@]}"; do
        if [ -x "$candidate" ]; then
            GEN_SNAPSHOT="$candidate"
            echo "  Found gen_snapshot after precache: $candidate"
            break
        fi
    done
fi

# ── MANDATORY CHECK: AOT is required for production builds ─────────────────
if [ -z "$GEN_SNAPSHOT" ]; then
    echo "ERROR: gen_snapshot binary not found for target '$ARCH'." >&2
    echo "       Release builds MUST use AOT compilation. Cannot produce a shippable Click." >&2
    echo "       Tried paths:" >&2
    for candidate in "${GEN_SNAPSHOT_CANDIDATES[@]}"; do
        echo "         $candidate" >&2
    done
    exit 1
fi

KERNEL_SNAPSHOT="$FLUTTER_BUILD_DIR/flutter_assets/kernel_blob.bin"
if [ ! -f "$KERNEL_SNAPSHOT" ]; then
    echo "ERROR: kernel_blob.bin not found at $KERNEL_SNAPSHOT" >&2
    echo "       'flutter build bundle --release' must have failed or not been run." >&2
    exit 1
fi

# Verify gen_snapshot is x86-64 (host-runnable on CI x64 runner)
GEN_SNAP_FILE="$(file "$GEN_SNAPSHOT")"
if ! echo "$GEN_SNAP_FILE" | grep -q "x86-64"; then
    echo "ERROR: gen_snapshot at '$GEN_SNAPSHOT' is not an x86-64 binary." >&2
    echo "       File: $GEN_SNAP_FILE" >&2
    echo "       For arm64 cross-build you need the clang_x64/gen_snapshot binary" >&2
    echo "       (x64-hosted, AArch64-targeting AOT compiler)." >&2
    exit 1
fi
echo "  [OK] gen_snapshot verified as x86-64 host binary: $GEN_SNAPSHOT"

# Determine gen_snapshot AOT flags per target architecture
case "$ARCH" in
    arm64) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so --no-sim-use-hardfp" ;;
    armhf) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so --sim-use-hardfp" ;;
    amd64) GEN_SNAPSHOT_ARCH_FLAGS="--snapshot-kind=app-aot-elf --elf=libapp.so" ;;
esac

LIB_DIR="$FLUTTER_BUILD_DIR/elinux/${ARCH}/release/bundle/lib"
mkdir -p "$LIB_DIR"

echo "Running gen_snapshot (AOT) for $ARCH → libapp.so ..."
(
    cd "$LIB_DIR"
    # shellcheck disable=SC2086
    "$GEN_SNAPSHOT" $GEN_SNAPSHOT_ARCH_FLAGS "$KERNEL_SNAPSHOT"
)

# ── Verify libapp.so was produced and has the correct target architecture ──
if [ ! -f "$LIB_DIR/libapp.so" ]; then
    echo "ERROR: gen_snapshot ran but libapp.so was NOT produced at $LIB_DIR/libapp.so" >&2
    exit 1
fi

LIBAPP_FILE="$(file "$LIB_DIR/libapp.so")"
echo "  libapp.so: $LIBAPP_FILE"
if [ -n "$ELF_ARCH_PATTERN" ] && ! echo "$LIBAPP_FILE" | grep -qi "$ELF_ARCH_PATTERN"; then
    echo "ERROR: libapp.so has wrong architecture!" >&2
    echo "       Expected pattern: $ELF_ARCH_PATTERN" >&2
    echo "       Got: $LIBAPP_FILE" >&2
    echo "       Possible cause: wrong gen_snapshot binary used (x64 instead of cross-targeting)." >&2
    exit 1
fi
echo "  [OK] libapp.so generated and verified for $ARCH at $LIB_DIR/libapp.so"

# ─── 7. Assemble bundle structure ─────────────────────────────────────────
BUNDLE_OUT="$FLUTTER_BUILD_DIR/elinux/${ARCH}/release/bundle"
mkdir -p "$BUNDLE_OUT/data"

if [ -d "$FLUTTER_BUILD_DIR/flutter_assets" ]; then
    cp -r "$FLUTTER_BUILD_DIR/flutter_assets" "$BUNDLE_OUT/data/"
fi

if [ -f "$ENGINE_DIR/icudtl.dat" ]; then
    cp "$ENGINE_DIR/icudtl.dat" "$BUNDLE_OUT/data/icudtl.dat"
    echo "  [OK] icudtl.dat copied to bundle"
else
    echo "ERROR: icudtl.dat not found in $ENGINE_DIR — engine cannot start without it." >&2
    exit 1
fi

# ─── 8. Assemble and validate Click package ───────────────────────────────
echo "Packaging Click..."
"$ROOT_DIR/scripts/package-click.sh" "$ARCH"

echo "=== MiniNotes build completed successfully for ${ARCH} ==="
