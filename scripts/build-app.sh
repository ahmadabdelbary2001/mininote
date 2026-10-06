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
        # amd64: gen_snapshot is a native x64 binary that emits x64 AOT
        # Artifact path in Flutter SDK cache:
        #   bin/cache/artifacts/engine/linux-x64/gen_snapshot
        GEN_SNAPSHOT_EXPECTED_DIR="linux-x64"
        ;;
    arm64)
        RUST_TARGET="aarch64-unknown-linux-gnu"
        LINKER="aarch64-linux-gnu-gcc"
        ELF_ARCH_PATTERN="aarch64"
        ELF_MACHINE_PATTERN="AArch64"
        # arm64 cross-build: gen_snapshot MUST be the x64-hosted AArch64-targeting binary.
        # It lives at: bin/cache/artifacts/engine/linux-arm64-release/clang_x64/gen_snapshot
        # The binary is x86-64 (runs on CI host) but emits AArch64 AOT instructions.
        # DO NOT use linux-x64/gen_snapshot — it emits x64 AOT, not AArch64.
        GEN_SNAPSHOT_EXPECTED_DIR="linux-arm64-release/clang_x64"
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
DART_BIN="$FLUTTER_ROOT/bin/dart"
DART_SDK="$FLUTTER_ROOT/bin/cache/dart-sdk"
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
echo "  Dart version:   $("$DART_BIN" --version 2>&1)"
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

# ─────────────────────────────────────────────────────────────────────────────
# PHASE A: Flutter Assets (NO kernel blob — assets only)
# ─────────────────────────────────────────────────────────────────────────────
build_flutter_assets() {
    echo ""
    echo "── Phase A: Building Flutter assets ──────────────────────────────────"
    local ASSET_OUT="$ROOT_DIR/build/flutter-bundle/$ARCH/flutter_assets"
    mkdir -p "$ASSET_OUT"

    (
        cd "$FLUTTER_APP"
        flutter pub get
        # --asset-dir writes ONLY assets (fonts, images, etc.) to the target dir.
        # It does NOT produce kernel_blob.bin here; the AOT kernel is built separately.
        flutter build bundle \
            --asset-dir="$ASSET_OUT" \
            --depfile="$ROOT_DIR/build/flutter-bundle/$ARCH/flutter_assets.d"
    )

    if [ ! -d "$ASSET_OUT" ]; then
        echo "ERROR: flutter build bundle produced no assets at $ASSET_OUT" >&2
        exit 1
    fi
    echo "  [OK] Flutter assets written to: $ASSET_OUT"
}

# ─────────────────────────────────────────────────────────────────────────────
# PHASE B: AOT kernel via frontend_server (produces app.dill)
# ─────────────────────────────────────────────────────────────────────────────
build_aot_kernel() {
    echo ""
    echo "── Phase B: Building AOT kernel (app.dill) ───────────────────────────"

    # Resolve frontend_server.dart.snapshot from the installed Flutter SDK
    local FRONTEND_SERVER=""
    local FRONTEND_CANDIDATES=(
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/frontend_server.dart.snapshot"
        "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot"
        "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/snapshots/kernel_worker.dart.snapshot"
    )
    for fc in "${FRONTEND_CANDIDATES[@]}"; do
        if [ -f "$fc" ]; then
            FRONTEND_SERVER="$fc"
            echo "  Found frontend_server: $fc"
            break
        fi
    done

    if [ -z "$FRONTEND_SERVER" ]; then
        echo "ERROR: frontend_server.dart.snapshot not found." >&2
        echo "Searched:" >&2
        for fc in "${FRONTEND_CANDIDATES[@]}"; do echo "    $fc" >&2; done
        # Attempt to populate cache
        echo "Attempting flutter precache --linux to fetch frontend_server..." >&2
        flutter precache --linux 2>/dev/null || true
        for fc in "${FRONTEND_CANDIDATES[@]}"; do
            if [ -f "$fc" ]; then
                FRONTEND_SERVER="$fc"
                echo "  Found frontend_server after precache: $fc"
                break
            fi
        done
    fi

    if [ -z "$FRONTEND_SERVER" ]; then
        echo "ERROR: frontend_server.dart.snapshot still not found after precache." >&2
        echo "Cannot build AOT kernel without frontend_server." >&2
        exit 1
    fi

    # Resolve flutter_patched_sdk_product
    local PATCHED_SDK=""
    local PATCHED_SDK_CANDIDATES=(
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/flutter_patched_sdk_product"
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/common/flutter_patched_sdk_product"
    )
    for ps in "${PATCHED_SDK_CANDIDATES[@]}"; do
        if [ -d "$ps" ]; then
            PATCHED_SDK="$ps"
            echo "  Found flutter_patched_sdk_product: $ps"
            break
        fi
    done

    if [ -z "$PATCHED_SDK" ]; then
        echo "ERROR: flutter_patched_sdk_product directory not found." >&2
        echo "Searched:" >&2
        for ps in "${PATCHED_SDK_CANDIDATES[@]}"; do echo "    $ps" >&2; done
        exit 1
    fi

    # Resolve package_config.json from the Flutter app
    local PKG_CONFIG="$FLUTTER_APP/.dart_tool/package_config.json"
    if [ ! -f "$PKG_CONFIG" ]; then
        echo "  Running 'flutter pub get' to generate package_config.json..."
        (cd "$FLUTTER_APP" && flutter pub get)
    fi
    if [ ! -f "$PKG_CONFIG" ]; then
        echo "ERROR: package_config.json not found at $PKG_CONFIG" >&2
        exit 1
    fi

    local AOT_KERNEL_DIR="$ROOT_DIR/build/flutter-bundle/$ARCH"
    local AOT_KERNEL_OUT="$AOT_KERNEL_DIR/app.dill"
    mkdir -p "$AOT_KERNEL_DIR"

    echo "  Building app.dill using frontend_server..."
    echo "    frontend_server: $FRONTEND_SERVER"
    echo "    patched_sdk:     $PATCHED_SDK"
    echo "    package_config:  $PKG_CONFIG"
    echo "    output:          $AOT_KERNEL_OUT"

    # The frontend_server AOT compilation flags per Flutter embedded linux docs:
    # --aot: enable AOT mode
    # --tfa: tree-shake based on full type analysis
    # -Ddart.vm.product=true: disable debug/assert overhead
    # -Ddart.vm.profile=false: not profiling
    # --packages: package_config.json
    # --sdk-root: flutter_patched_sdk_product (contains dart platform libs)
    # --target=flutter: Flutter embedding target
    # --output-dill: output path
    # The final positional arg is main.dart (entrypoint)
    "$DART_BIN" \
        "$FRONTEND_SERVER" \
        --target=flutter \
        --sdk-root="$PATCHED_SDK/" \
        --packages="$PKG_CONFIG" \
        --aot \
        --tfa \
        -Ddart.vm.product=true \
        -Ddart.vm.profile=false \
        --output-dill="$AOT_KERNEL_OUT" \
        "$FLUTTER_APP/lib/main.dart"

    if [ ! -f "$AOT_KERNEL_OUT" ]; then
        echo "ERROR: frontend_server completed but app.dill was NOT produced at $AOT_KERNEL_OUT" >&2
        exit 1
    fi

    local DILL_SIZE
    DILL_SIZE="$(wc -c < "$AOT_KERNEL_OUT")"
    if [ "$DILL_SIZE" -lt 4096 ]; then
        echo "ERROR: app.dill is suspiciously small ($DILL_SIZE bytes) — compilation likely failed." >&2
        exit 1
    fi

    echo "  [OK] app.dill produced: $AOT_KERNEL_OUT ($DILL_SIZE bytes)"

    # Export for downstream use
    AOT_KERNEL="$AOT_KERNEL_OUT"
    echo "$AOT_KERNEL" > "$AOT_KERNEL_DIR/app.dill.path"
}

# ─────────────────────────────────────────────────────────────────────────────
# gen_snapshot resolver: architecture-aware, deterministic, no fallback
# ─────────────────────────────────────────────────────────────────────────────
resolve_gen_snapshot() {
    echo ""
    echo "── Resolving gen_snapshot ────────────────────────────────────────────"
    echo "  Target arch:          $ARCH"
    echo "  Engine SHA:           $ENGINE_SHA"
    echo "  Expected cache dir:   $GEN_SNAPSHOT_EXPECTED_DIR"

    GEN_SNAPSHOT=""
    local EXPECTED_PATH="$FLUTTER_ROOT/bin/cache/artifacts/engine/$GEN_SNAPSHOT_EXPECTED_DIR/gen_snapshot"

    # Step 1: Check the architecture-specific cache path ONLY
    if [ -x "$EXPECTED_PATH" ]; then
        GEN_SNAPSHOT="$EXPECTED_PATH"
        echo "  Found gen_snapshot (cache): $GEN_SNAPSHOT"
    fi

    # Step 2: If not in cache, fetch from Flutter infrastructure (exact Engine SHA)
    if [ -z "$GEN_SNAPSHOT" ]; then
        echo "  gen_snapshot not in cache at $EXPECTED_PATH"
        echo "  Attempting to fetch from Flutter infrastructure (Engine SHA: $ENGINE_SHA)..."

        local FETCH_DIR
        FETCH_DIR="$(mktemp -d)"
        local BASE_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}"

        case "$ARCH" in
            amd64)
                # linux-x64 gen_snapshot is inside linux-x64/artifacts.zip or linux-x64/linux-x64.zip
                local FETCH_URL="${BASE_URL}/linux-x64/linux-x64.zip"
                if curl -sSLf --max-time 180 "$FETCH_URL" -o "$FETCH_DIR/engine.zip" 2>/dev/null; then
                    unzip -q -o "$FETCH_DIR/engine.zip" "gen_snapshot" -d "$FETCH_DIR" 2>/dev/null || true
                    if [ ! -f "$FETCH_DIR/gen_snapshot" ]; then
                        # Some archives have it at root, some in subdir
                        unzip -q -o "$FETCH_DIR/engine.zip" -d "$FETCH_DIR" 2>/dev/null || true
                    fi
                    if [ -f "$FETCH_DIR/gen_snapshot" ]; then
                        chmod +x "$FETCH_DIR/gen_snapshot"
                        GEN_SNAPSHOT="$FETCH_DIR/gen_snapshot"
                        echo "  Fetched gen_snapshot from: $FETCH_URL"
                    fi
                fi
                ;;
            arm64)
                # The cross-build gen_snapshot for arm64 lives in:
                # linux-arm64-release/clang_x64/gen_snapshot  (inside linux-arm64-release.zip)
                local FETCH_URL="${BASE_URL}/linux-arm64-release/linux-arm64-release.zip"
                if curl -sSLf --max-time 180 "$FETCH_URL" -o "$FETCH_DIR/engine.zip" 2>/dev/null; then
                    unzip -q -o "$FETCH_DIR/engine.zip" -d "$FETCH_DIR" 2>/dev/null || true
                    if [ -f "$FETCH_DIR/clang_x64/gen_snapshot" ]; then
                        chmod +x "$FETCH_DIR/clang_x64/gen_snapshot"
                        GEN_SNAPSHOT="$FETCH_DIR/clang_x64/gen_snapshot"
                        echo "  Fetched arm64 gen_snapshot (clang_x64) from: $FETCH_URL"
                    elif [ -f "$FETCH_DIR/gen_snapshot" ]; then
                        # Sanity: it must be x86-64 to run on CI host
                        chmod +x "$FETCH_DIR/gen_snapshot"
                        GEN_SNAPSHOT="$FETCH_DIR/gen_snapshot"
                        echo "  Fetched gen_snapshot from: $FETCH_URL"
                    fi
                fi
                ;;
        esac
    fi

    # Step 3: Try flutter precache as last resort before failing
    if [ -z "$GEN_SNAPSHOT" ]; then
        echo "  Attempting 'flutter precache --linux' to populate cache..."
        flutter precache --linux 2>/dev/null || true
        if [ -x "$EXPECTED_PATH" ]; then
            GEN_SNAPSHOT="$EXPECTED_PATH"
            echo "  Found gen_snapshot after precache: $GEN_SNAPSHOT"
        fi
    fi

    # ── HARD FAIL: no acceptable gen_snapshot found ──────────────────────────
    if [ -z "$GEN_SNAPSHOT" ]; then
        echo "" >&2
        echo "FATAL ERROR: Cannot find architecture-specific gen_snapshot for $ARCH." >&2
        echo "" >&2
        echo "  For $ARCH, the required binary is:" >&2
        echo "    $EXPECTED_PATH" >&2
        echo "" >&2
        if [ "$ARCH" = "arm64" ]; then
            echo "  This is the x64-hosted, AArch64-targeting AOT compiler." >&2
            echo "  It is NOT the same as linux-x64/gen_snapshot (which emits x64 AOT)." >&2
            echo "  DO NOT fall back to linux-x64/gen_snapshot for arm64 — this is wrong." >&2
        fi
        echo "" >&2
        echo "  Engine SHA: $ENGINE_SHA" >&2
        echo "  Expected Flutter infra URL (arm64):" >&2
        echo "    https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}/linux-arm64-release/linux-arm64-release.zip" >&2
        echo "" >&2
        echo "  If the artifact is missing from Flutter infra for this SHA," >&2
        echo "  the engine must be built from source at revision: $ENGINE_SHA" >&2
        exit 1
    fi

    # ── Validate: gen_snapshot must be x86-64 (host-runnable on CI) ──────────
    local GS_FILE_OUT
    GS_FILE_OUT="$(file "$GEN_SNAPSHOT")"
    echo "  gen_snapshot file: $GS_FILE_OUT"

    if ! echo "$GS_FILE_OUT" | grep -q "x86-64"; then
        echo "" >&2
        echo "FATAL ERROR: gen_snapshot at '$GEN_SNAPSHOT' is NOT an x86-64 binary." >&2
        echo "  It cannot run on the x86-64 CI host." >&2
        echo "  File: $GS_FILE_OUT" >&2
        echo "  For arm64 cross-build you need clang_x64/gen_snapshot" >&2
        echo "  (x64-executable, AArch64-targeting AOT compiler)." >&2
        exit 1
    fi

    # ── Log gen_snapshot --version for traceability ───────────────────────────
    echo "  gen_snapshot --version:"
    local GS_VERSION
    if GS_VERSION="$("$GEN_SNAPSHOT" --version 2>&1)"; then
        echo "    $GS_VERSION"
        # For arm64: --version should contain "simarm64" or "linux_arm64" or similar
        # indicating it targets AArch64 even though it runs on x64
        if [ "$ARCH" = "arm64" ]; then
            if echo "$GS_VERSION" | grep -qi -E "(arm64|aarch64|simarm64|linux_arm64)"; then
                echo "  [OK] gen_snapshot --version confirms arm64 target"
            else
                echo "  [WARN] gen_snapshot --version does not explicitly mention arm64." >&2
                echo "         Version string: $GS_VERSION" >&2
                echo "         Continuing — verify libapp.so arch after compilation." >&2
            fi
        fi
    else
        echo "    (--version returned non-zero; this is non-fatal for older gen_snapshot)" >&2
    fi

    echo "  [OK] gen_snapshot resolved: $GEN_SNAPSHOT"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase C: Build libapp.so (AOT ELF) from app.dill
# ─────────────────────────────────────────────────────────────────────────────
build_aot_library() {
    echo ""
    echo "── Phase C: Building libapp.so (AOT ELF) ─────────────────────────────"
    echo "  Input (AOT kernel): $AOT_KERNEL"
    echo "  gen_snapshot:       $GEN_SNAPSHOT"

    local AOT_LIB_DIR="$ROOT_DIR/build/flutter-bundle/$ARCH/lib"
    mkdir -p "$AOT_LIB_DIR"

    # gen_snapshot flags per Flutter docs for ELF AOT:
    # --deterministic: reproducible output
    # --snapshot_kind=app-aot-elf: ELF shared library (not assembly)
    # --elf=<output>: output path for libapp.so
    # --strip: strip debug symbols for smaller size (production)
    # <app.dill>: the AOT kernel from frontend_server
    #
    # NOTE: NO --sim-use-hardfp or --no-sim-use-hardfp — these were arm32 simulator
    # flags removed in Flutter 3.x. They are INVALID for arm64/amd64.
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
    echo "  [OK] libapp.so produced: $AOT_LIB"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase D: Validate libapp.so architecture
# ─────────────────────────────────────────────────────────────────────────────
validate_aot_library() {
    echo ""
    echo "── Phase D: Validating libapp.so architecture ────────────────────────"

    local LIBAPP_FILE_OUT
    LIBAPP_FILE_OUT="$(file "$AOT_LIB")"
    echo "  file output: $LIBAPP_FILE_OUT"

    if ! echo "$LIBAPP_FILE_OUT" | grep -qi "$ELF_ARCH_PATTERN"; then
        echo "" >&2
        echo "FATAL ERROR: libapp.so has WRONG architecture!" >&2
        echo "  Expected:   $ELF_ARCH_PATTERN" >&2
        echo "  Got:        $LIBAPP_FILE_OUT" >&2
        if [ "$ARCH" = "arm64" ]; then
            echo "  This means the WRONG gen_snapshot was used (likely linux-x64/gen_snapshot)." >&2
            echo "  For arm64, ONLY linux-arm64-release/clang_x64/gen_snapshot is acceptable." >&2
        fi
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
build_flutter_assets
build_aot_kernel
resolve_gen_snapshot
build_aot_library
validate_aot_library

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

# Production release bundle must NOT contain debug-only artifacts:
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
