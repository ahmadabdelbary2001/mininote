#!/bin/bash
# =============================================================================
# build-app.sh — MiniNotes Ubuntu Touch build pipeline
# =============================================================================
# AOT Pipeline (correct order):
#   1. flutter build bundle --asset-dir=...  → flutter_assets/ (no kernel)
#   2. dart frontend_server.dart.snapshot    → app.dill (true AOT kernel)
#   3. gen_snapshot (arch-specific)         → libapp.so (AOT ELF)
#   4. Assemble bundle + Click
#
# References:
#   https://github.com/flutter/flutter/blob/master/docs/engine/Custom-Flutter-Engine-Embedding-in-AOT-Mode.md
#   https://github.com/sony/flutter-embedded-linux/wiki/Building-Flutter-apps
# =============================================================================
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FLUTTER_APP="$ROOT_DIR/flutter_app"

echo "=== Building MiniNotes for Ubuntu Touch (${ARCH}) ==="

# ─── Architecture-specific settings ──────────────────────────────────────────
case "$ARCH" in
    amd64)
        RUST_TARGET="x86_64-unknown-linux-gnu"
        LINKER="gcc"
        ELF_ARCH_PATTERN="x86-64"
        ELF_MACHINE_PATTERN="Advanced Micro Devices X86-64"
        # amd64: release gen_snapshot lives in linux-x64-release/gen_snapshot
        GEN_SNAPSHOT_EXPECTED_DIR="linux-x64-release"
        ;;
    arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        ELF_ARCH_PATTERN="aarch64"
        ELF_MACHINE_PATTERN="AArch64"
        # arm64 cross-build: x64-hosted AArch64-targeting gen_snapshot
        GEN_SNAPSHOT_EXPECTED_DIR="android-arm64-release/linux-x64"
        ;;
    armhf)
        echo "=========================================================================="
        echo "NOTICE: Flutter Engine arm32 artifacts discontinued for Flutter >= 3.10."
        echo "All Ubuntu Touch production devices run arm64. Skipping armhf gracefully."
        echo "=========================================================================="
        mkdir -p "$ROOT_DIR/dist"
        echo "armhf skipped: arm32 engine unavailable upstream for Flutter >= 3.10" \
            > "$ROOT_DIR/dist/armhf-skipped.txt"
        exit 0
        ;;
    *)
        echo "ERROR: Unsupported architecture $ARCH" >&2
        exit 1
        ;;
esac

# ─── Resolve Flutter SDK paths ────────────────────────────────────────────────
FLUTTER_BIN="$(which flutter)"
FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"
ENGINE_STAMP="$FLUTTER_ROOT/bin/internal/engine.version"

if [ ! -f "$ENGINE_STAMP" ]; then
    echo "ERROR: engine.version stamp not found at $ENGINE_STAMP" >&2
    echo "       Run 'flutter precache --linux' first." >&2
    exit 1
fi
ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_STAMP")"

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Flutter SDK:    $(flutter --version --machine 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('frameworkVersion','?'))" 2>/dev/null || flutter --version 2>&1 | head -1)"
echo "  Engine SHA:     $ENGINE_SHA"
echo "  Flutter root:   $FLUTTER_ROOT"
echo "  Target arch:    $ARCH"
echo "══════════════════════════════════════════════════════════"
echo ""

# ─── 1. Fetch matching Flutter engine artifacts ───────────────────────────────
"$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH" "$ENGINE_SHA"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"

# ─── 2. Build flutter-embedded-linux Wayland embedder ────────────────────────
"$ROOT_DIR/scripts/build-embedder.sh" "$ARCH"

# ─── 3. Build native_core (Rust cdylib) ──────────────────────────────────────
echo "Building native_core ($RUST_TARGET)..."
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$ROOT_DIR/native_core/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# ─── 4. Build mininote runner (Rust binary) ───────────────────────────────────
echo "Building mininote runner ($RUST_TARGET)..."
FLUTTER_ENGINE_LIB_DIR="$ENGINE_DIR" \
RUSTFLAGS="-C linker=$LINKER" cargo build \
    --manifest-path "$FLUTTER_APP/elinux/runner/Cargo.toml" \
    --release \
    --target "$RUST_TARGET"

# =============================================================================
# PHASE A: Build Flutter bundle assets
# =============================================================================
build_flutter_bundle() {
    echo ""
    echo "── Phase A: Building Flutter bundle assets ───────────────────────────"

    (
        cd "$FLUTTER_APP"
        flutter pub get
        flutter build bundle
    )

    # Copy assets to our bundle directory
    local ASSET_OUT="$ROOT_DIR/build/flutter-bundle/$ARCH/flutter_assets"
    mkdir -p "$ASSET_OUT"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$FLUTTER_APP/build/flutter_assets/" "$ASSET_OUT/"
    else
        cp -r "$FLUTTER_APP/build/flutter_assets/." "$ASSET_OUT/"
    fi
    # Clean up JIT-only artifacts from the assets directory
    rm -f "$ASSET_OUT/kernel_blob.bin" "$ASSET_OUT/vm_snapshot_data" "$ASSET_OUT/isolate_snapshot_data"
    echo "  [OK] Flutter assets copied to: $ASSET_OUT"
}

# =============================================================================
# PHASE B: Build true AOT kernel (app.dill) via frontend_server
# =============================================================================
build_aot_kernel() {
    echo ""
    echo "── Phase B: Building AOT kernel (app.dill) ───────────────────────────"

    # 1. Locate frontend_server snapshot
    local FRONTEND_SERVER=""
    for fs_candidate in \
        "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot" \
        "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot" \
        "$ENGINE_DIR/frontend_server.dart.snapshot"; do
        if [ -f "$fs_candidate" ]; then
            FRONTEND_SERVER="$fs_candidate"
            break
        fi
    done

    if [ -z "$FRONTEND_SERVER" ]; then
        echo "ERROR: frontend_server snapshot not found." >&2
        echo "       Searched in: $FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots/" >&2
        exit 1
    fi
    echo "  frontend_server: $FRONTEND_SERVER"

    # 2. Locate Dart runner
    local DART_BIN="$FLUTTER_ROOT/bin/dart"
    if [[ "$FRONTEND_SERVER" == *"frontend_server_aot"* ]] && [ -x "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dartaotruntime" ]; then
        DART_BIN="$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dartaotruntime"
    fi
    echo "  Dart runner:     $DART_BIN"

    # 3. Locate flutter_patched_sdk_product
    local SDK_ROOT=""
    for sdk_candidate in \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/common/flutter_patched_sdk_product" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/common/flutter_patched_sdk" \
        "$ENGINE_DIR/flutter_patched_sdk_product"; do
        if [ -d "$sdk_candidate" ]; then
            SDK_ROOT="$sdk_candidate"
            break
        fi
    done

    if [ -z "$SDK_ROOT" ]; then
        echo "ERROR: flutter_patched_sdk_product not found." >&2
        echo "       Searched in: $FLUTTER_ROOT/bin/cache/artifacts/engine/common/" >&2
        exit 1
    fi
    echo "  SDK root:        $SDK_ROOT"

    local DILL_OUT="$FLUTTER_APP/build/app.dill"
    mkdir -p "$(dirname "$DILL_OUT")"

    echo "  Compiling Dart sources to AOT kernel (app.dill)..."
    "$DART_BIN" "$FRONTEND_SERVER" \
        --sdk-root "$SDK_ROOT/" \
        --target=flutter \
        --no-print-incremental-dependencies \
        -Ddart.vm.profile=false \
        -Ddart.vm.product=true \
        --delete-tostring-package-uri=dart:ui \
        --delete-tostring-package-uri=package:flutter \
        --aot \
        --tfa \
        --target-os linux \
        --packages "$FLUTTER_APP/.dart_tool/package_config.json" \
        --output-dill "$DILL_OUT" \
        package:mininote/main.dart

    if [ ! -f "$DILL_OUT" ] || [ ! -s "$DILL_OUT" ]; then
        echo "ERROR: frontend_server failed to produce AOT kernel at $DILL_OUT" >&2
        exit 1
    fi

    local DILL_SIZE
    DILL_SIZE="$(wc -c < "$DILL_OUT")"
    echo "  [OK] app.dill produced: $DILL_OUT ($DILL_SIZE bytes)"
    AOT_KERNEL="$DILL_OUT"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase C: gen_snapshot resolver (architecture-specific, deterministic)
# ─────────────────────────────────────────────────────────────────────────────
resolve_gen_snapshot() {
    echo ""
    echo "── Phase C: Resolving gen_snapshot ───────────────────────────────────"
    echo "  Target arch:          $ARCH"
    echo "  Engine SHA:           $ENGINE_SHA"
    echo "  Expected cache dir:   $GEN_SNAPSHOT_EXPECTED_DIR"

    GEN_SNAPSHOT=""

    local CANDIDATES=()
    if [ "$ARCH" = "amd64" ]; then
        CANDIDATES+=(
            "$ENGINE_DIR/gen_snapshot"
            "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64-release/gen_snapshot"
            "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/gen_snapshot"
        )
    elif [ "$ARCH" = "arm64" ]; then
        CANDIDATES+=(
            "$ENGINE_DIR/gen_snapshot"
            "$ENGINE_DIR/gen_snapshot_arm64_cross"
            "$FLUTTER_ROOT/bin/cache/artifacts/engine/android-arm64-release/linux-x64/gen_snapshot"
            "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-arm64-release/clang_x64/gen_snapshot"
        )
    fi

    for candidate in "${CANDIDATES[@]}"; do
        if [ -x "$candidate" ]; then
            # Verify it is runnable on the host (x86-64)
            if file "$candidate" | grep -q "x86-64"; then
                if [ "$ARCH" = "arm64" ]; then
                    local VER_STR
                    VER_STR="$("$candidate" --version 2>&1 || true)"
                    if echo "$VER_STR" | grep -qi -E "(arm64|aarch64|simarm64)"; then
                        GEN_SNAPSHOT="$candidate"
                        echo "  Found arm64 cross gen_snapshot: $GEN_SNAPSHOT"
                        break
                    fi
                else
                    GEN_SNAPSHOT="$candidate"
                    echo "  Found amd64 gen_snapshot: $GEN_SNAPSHOT"
                    break
                fi
            fi
        fi
    done

    # If not found, run fetch-engine-artifacts.sh
    if [ -z "$GEN_SNAPSHOT" ]; then
        echo "  gen_snapshot not found in cache. Running fetch-engine-artifacts.sh..."
        "$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH" "$ENGINE_SHA"
        for candidate in "${CANDIDATES[@]}"; do
            if [ -x "$candidate" ] && file "$candidate" | grep -q "x86-64"; then
                GEN_SNAPSHOT="$candidate"
                echo "  Found gen_snapshot after fetch: $GEN_SNAPSHOT"
                break
            fi
        done
    fi

    if [ -z "$GEN_SNAPSHOT" ]; then
        echo "" >&2
        echo "FATAL ERROR: Cannot find architecture-specific gen_snapshot for $ARCH." >&2
        exit 1
    fi

    echo "  gen_snapshot file: $(file "$GEN_SNAPSHOT")"
    echo "  gen_snapshot version: $("$GEN_SNAPSHOT" --version 2>&1 | head -1 || true)"
    echo "  [OK] gen_snapshot resolved: $GEN_SNAPSHOT"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase D: Build libapp.so (AOT ELF) from app.dill
# ─────────────────────────────────────────────────────────────────────────────
build_aot_library() {
    echo ""
    echo "── Phase D: Building libapp.so (AOT ELF) ─────────────────────────────"
    echo "  Input (AOT kernel): $AOT_KERNEL"
    echo "  gen_snapshot:       $GEN_SNAPSHOT"

    local AOT_LIB_DIR="$ROOT_DIR/build/flutter-bundle/$ARCH/lib"
    mkdir -p "$AOT_LIB_DIR"

    echo "  Running gen_snapshot..."
    "$GEN_SNAPSHOT" \
        --deterministic \
        --snapshot_kind=app-aot-elf \
        --elf="$AOT_LIB_DIR/libapp.so" \
        --strip \
        "$AOT_KERNEL"

    if [ ! -f "$AOT_LIB_DIR/libapp.so" ]; then
        echo "ERROR: gen_snapshot completed but libapp.so was NOT produced at $AOT_LIB_DIR/libapp.so" >&2
        exit 1
    fi

    AOT_LIB="$AOT_LIB_DIR/libapp.so"
    echo "  [OK] libapp.so produced: $AOT_LIB ($(wc -c < "$AOT_LIB") bytes)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase E: Validate libapp.so architecture
# ─────────────────────────────────────────────────────────────────────────────
validate_aot_library() {
    echo ""
    echo "── Phase E: Validating libapp.so architecture ────────────────────────"

    local LIBAPP_FILE_OUT
    LIBAPP_FILE_OUT="$(file "$AOT_LIB")"
    echo "  file output: $LIBAPP_FILE_OUT"

    if ! echo "$LIBAPP_FILE_OUT" | grep -qi "$ELF_ARCH_PATTERN"; then
        echo "" >&2
        echo "FATAL ERROR: libapp.so has WRONG architecture!" >&2
        echo "  Expected:   $ELF_ARCH_PATTERN" >&2
        echo "  Got:        $LIBAPP_FILE_OUT" >&2
        exit 1
    fi

    # readelf machine type check
    if command -v readelf >/dev/null 2>&1; then
        local MACHINE
        MACHINE="$(readelf -h "$AOT_LIB" 2>/dev/null | grep 'Machine:' | head -1 | sed 's/.*Machine: *//')"
        echo "  readelf Machine: $MACHINE"
        if ! echo "$MACHINE" | grep -qi "$ELF_MACHINE_PATTERN"; then
            echo "" >&2
            echo "FATAL ERROR: libapp.so readelf Machine does not match expected!" >&2
            echo "  Expected pattern: $ELF_MACHINE_PATTERN" >&2
            echo "  Got:              $MACHINE" >&2
            exit 1
        fi
        echo "  [OK] libapp.so Machine type verified: $MACHINE"
    fi

    echo "  [OK] libapp.so architecture validation passed for $ARCH"
}

# ─────────────────────────────────────────────────────────────────────────────
# Execute the AOT pipeline phases
# ─────────────────────────────────────────────────────────────────────────────
build_flutter_bundle     # Phase A: Flutter assets
build_aot_kernel         # Phase B: frontend_server -> app.dill
resolve_gen_snapshot     # Phase C: architecture-specific gen_snapshot
build_aot_library        # Phase D: gen_snapshot -> libapp.so
validate_aot_library     # Phase E: readelf & file arch check

# ─── 7. Assemble bundle structure ─────────────────────────────────────────────
echo ""
echo "── Assembling bundle ─────────────────────────────────────────────────────"
BUNDLE_BASE="$ROOT_DIR/build/flutter-bundle/$ARCH"
BUNDLE_OUT="$BUNDLE_BASE/bundle"
mkdir -p "$BUNDLE_OUT/lib"
mkdir -p "$BUNDLE_OUT/data"

# Copy flutter_assets
if [ -d "$BUNDLE_BASE/flutter_assets" ]; then
    cp -r "$BUNDLE_BASE/flutter_assets" "$BUNDLE_OUT/data/"
    echo "  [OK] Copied flutter_assets"
else
    echo "ERROR: flutter_assets not found at $BUNDLE_BASE/flutter_assets" >&2
    exit 1
fi

# Copy icudtl.dat
if [ -f "$ENGINE_DIR/icudtl.dat" ]; then
    cp "$ENGINE_DIR/icudtl.dat" "$BUNDLE_OUT/data/icudtl.dat"
    echo "  [OK] Copied icudtl.dat"
else
    echo "ERROR: icudtl.dat not found in $ENGINE_DIR — engine cannot start." >&2
    exit 1
fi

# Copy libapp.so (AOT ELF)
cp "$AOT_LIB" "$BUNDLE_OUT/lib/libapp.so"
echo "  [OK] Copied libapp.so (AOT)"

# Production release bundle must NOT contain JIT-only artifacts.
# kernel_blob.bin is included in the bundle for the embedder to use when
# libapp.so fails to load (fallback), but some eLinux embedders don't need it.
# For our production AOT-only build, remove it to ensure pure AOT delivery.
for debug_artifact in "kernel_blob.bin" "vm_snapshot_data" "isolate_snapshot_data"; do
    if [ -f "$BUNDLE_OUT/data/flutter_assets/$debug_artifact" ]; then
        echo "  [INFO] Removing JIT-only artifact from release bundle: $debug_artifact"
        rm -f "$BUNDLE_OUT/data/flutter_assets/$debug_artifact"
    fi
done

echo ""
echo "Bundle layout:"
find "$BUNDLE_OUT" -type f | sort | sed 's|.*bundle/||'

# ─── 8. Assemble and validate Click package ────────────────────────────────────
echo ""
echo "── Packaging Click ───────────────────────────────────────────────────────"
"$ROOT_DIR/scripts/package-click.sh" "$ARCH" "$BUNDLE_OUT"

echo ""
echo "=== MiniNotes build completed successfully for ${ARCH} ==="
