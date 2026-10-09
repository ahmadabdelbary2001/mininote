#!/bin/bash
# =============================================================================
# fetch-engine-artifacts.sh — Fetch Flutter engine artifacts for target arch
# =============================================================================
# Artifacts fetched:
#   - libflutter_engine.so   (Flutter embedder engine library)
#   - flutter_embedder.h     (C embedder API header)
#   - icudtl.dat             (ICU data, architecture-independent)
#   - gen_snapshot           (for amd64: linux-x64; for arm64: clang_x64)
#   - frontend_server.dart.snapshot  (Dart frontend compiler)
#   - flutter_patched_sdk_product/   (AOT platform libraries)
#
# All artifacts must be from the SAME Engine SHA as the installed Flutter SDK
# to guarantee compatibility between libflutter_engine.so and gen_snapshot.
# =============================================================================
set -euo pipefail

ARCH="${1:-}"
ENGINE_SHA="${2:-}"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <arch> [engine_sha]" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

# ── Resolve Flutter ROOT (always) and Engine SHA ─────────────────────────────
FLUTTER_ROOT=""
if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(which flutter)"
    FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"
fi

if [ -z "$ENGINE_SHA" ]; then
    if [ -n "$FLUTTER_ROOT" ]; then
        ENGINE_STAMP="$FLUTTER_ROOT/bin/internal/engine.version"
        if [ -f "$ENGINE_STAMP" ]; then
            ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_STAMP")"
        fi
    fi
fi

if [ -z "$ENGINE_SHA" ]; then
    # Hardcoded SHA for Flutter 3.41.7 (fallback only if Flutter not installed)
    ENGINE_SHA="59aa584fdf100e6c78c785d8a5b565d1de4b48ab"
    echo "WARNING: Using hardcoded Engine SHA (Flutter SDK not found): $ENGINE_SHA" >&2
fi

echo "Fetching engine artifacts for $ARCH (Engine SHA: $ENGINE_SHA)..."

case "$ARCH" in
    amd64|x86_64)
        FLUTTER_TARGET="linux-x64"
        ARMHF_FALLBACK=false
        ;;
    arm64|aarch64)
        FLUTTER_TARGET="linux-arm64"
        ARMHF_FALLBACK=false
        ;;
    armhf|arm)
        # arm32 engine not published for Flutter >= 3.10
        FLUTTER_TARGET="linux-arm"
        ARMHF_FALLBACK=true
        ;;
    *)
        echo "ERROR: Unknown architecture $ARCH" >&2
        exit 1
        ;;
esac

DEST_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"
mkdir -p "$DEST_DIR"

BASE_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}"

TMP_ZIP="$(mktemp --suffix=.zip)"
trap 'rm -f "$TMP_ZIP"' EXIT

# ── 1. Download embedder zip (libflutter_engine.so + flutter_embedder.h) ─────
EMBEDDER_ZIP_URL="${BASE_URL}/${FLUTTER_TARGET}/${FLUTTER_TARGET}-embedder.zip"
echo "Downloading embedder from: $EMBEDDER_ZIP_URL"
if curl -sSLf "$EMBEDDER_ZIP_URL" -o "$TMP_ZIP"; then
    echo "Extracting embedder artifacts..."
    unzip -q -o "$TMP_ZIP" -d "$DEST_DIR"
else
    if [ "$ARMHF_FALLBACK" = "true" ]; then
        echo "WARNING: armhf embedder zip not found on CDN (Flutter dropped arm32 support)."
        echo "         armhf build will be skipped — expected for Flutter >= 3.10."
    else
        echo "ERROR: Embedder zip not found at $EMBEDDER_ZIP_URL" >&2
        exit 1
    fi
fi

# ── 2. Download icudtl.dat if not present ─────────────────────────────────────
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    ICU_URL="${BASE_URL}/${FLUTTER_TARGET}/artifacts.zip"
    echo "Fetching icudtl.dat from $ICU_URL..."
    if curl -sSLf "$ICU_URL" -o "$TMP_ZIP" 2>/dev/null; then
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" 2>/dev/null || true
    fi
fi

# Final fallback: linux-x64 always has icudtl.dat (architecture-independent)
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    echo "Fetching icudtl.dat from linux-x64 fallback..."
    if curl -sSLf "${BASE_URL}/linux-x64/artifacts.zip" -o "$TMP_ZIP"; then
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" 2>/dev/null || true
    fi
fi

# ── 3. Download arch-specific gen_snapshot ────────────────────────────────────
# CRITICAL: gen_snapshot must match the Engine SHA AND target architecture.
# For amd64: linux-x64/gen_snapshot  (x64 host, x64 target)
# For arm64: linux-arm64-release/clang_x64/gen_snapshot  (x64 host, arm64 target)
echo ""
echo "Fetching gen_snapshot for $ARCH..."

case "$ARCH" in
    amd64|x86_64)
        GS_DEST="$DEST_DIR/gen_snapshot"
        # 1. Check local Flutter SDK cache first
        if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64-release/gen_snapshot" ]; then
            cp "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64-release/gen_snapshot" "$GS_DEST"
            chmod +x "$GS_DEST"
            echo "  [OK] Copied gen_snapshot from Flutter cache (linux-x64-release)"
        fi
        # 2. If not found, download from linux-x64-release/linux-x64-flutter-gtk.zip
        if [ ! -f "$GS_DEST" ]; then
            GS_URL="${BASE_URL}/linux-x64-release/linux-x64-flutter-gtk.zip"
            if curl -sSLf --max-time 180 "$GS_URL" -o "$TMP_ZIP" 2>/dev/null; then
                unzip -q -o "$TMP_ZIP" "gen_snapshot" -d "$DEST_DIR" 2>/dev/null || true
                if [ -f "$GS_DEST" ]; then
                    chmod +x "$GS_DEST"
                    echo "  [OK] gen_snapshot (amd64) extracted from: $GS_URL"
                    if [ -n "$FLUTTER_ROOT" ]; then
                        mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64-release"
                        cp "$GS_DEST" "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64-release/gen_snapshot"
                    fi
                fi
            fi
        fi
        ;;
    arm64|aarch64)
        GS_DEST="$DEST_DIR/gen_snapshot"
        GS_CROSS="$DEST_DIR/gen_snapshot_arm64_cross"
        # 1. Check local Flutter SDK cache (android-arm64-release/linux-x64/gen_snapshot)
        if [ -n "$FLUTTER_ROOT" ] && [ -x "$FLUTTER_ROOT/bin/cache/artifacts/engine/android-arm64-release/linux-x64/gen_snapshot" ]; then
            cp "$FLUTTER_ROOT/bin/cache/artifacts/engine/android-arm64-release/linux-x64/gen_snapshot" "$GS_DEST"
            cp "$GS_DEST" "$GS_CROSS"
            chmod +x "$GS_DEST" "$GS_CROSS"
            echo "  [OK] Copied arm64 cross gen_snapshot from Flutter cache (android-arm64-release/linux-x64)"
        fi
        # 2. If not found, download from android-arm64-release/linux-x64.zip
        if [ ! -f "$GS_DEST" ]; then
            GS_URL="${BASE_URL}/android-arm64-release/linux-x64.zip"
            if curl -sSLf --max-time 180 "$GS_URL" -o "$TMP_ZIP" 2>/dev/null; then
                unzip -q -o "$TMP_ZIP" "gen_snapshot" -d "$DEST_DIR" 2>/dev/null || true
                if [ -f "$GS_DEST" ]; then
                    cp "$GS_DEST" "$GS_CROSS"
                    chmod +x "$GS_DEST" "$GS_CROSS"
                    echo "  [OK] gen_snapshot (arm64 cross) extracted from: $GS_URL"
                    if [ -n "$FLUTTER_ROOT" ]; then
                        mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/android-arm64-release/linux-x64"
                        cp "$GS_DEST" "$FLUTTER_ROOT/bin/cache/artifacts/engine/android-arm64-release/linux-x64/gen_snapshot"
                        mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-arm64-release/clang_x64"
                        cp "$GS_DEST" "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-arm64-release/clang_x64/gen_snapshot"
                    fi
                fi
            fi
        fi
        ;;
esac

# ── 4. Download frontend_server.dart.snapshot ─────────────────────────────────
# frontend_server is always from linux-x64 (it runs on the host).
echo ""
echo "Fetching frontend_server.dart.snapshot..."
FS_URL="${BASE_URL}/linux-x64/linux-x64.zip"
FS_DEST="$DEST_DIR/frontend_server.dart.snapshot"
if [ ! -f "$FS_DEST" ]; then
    if curl -sSLf --max-time 180 "$FS_URL" -o "$TMP_ZIP" 2>/dev/null; then
        unzip -q -o "$TMP_ZIP" "frontend_server.dart.snapshot" -d "$DEST_DIR" 2>/dev/null || true
        if [ -f "$FS_DEST" ]; then
            echo "  [OK] frontend_server.dart.snapshot extracted to: $FS_DEST"
        else
            echo "  INFO: frontend_server.dart.snapshot not in linux-x64.zip (will use SDK cache)"
        fi
    fi
fi

# ── 5. Download flutter_patched_sdk_product ────────────────────────────────────
echo ""
echo "Fetching flutter_patched_sdk_product..."
PSK_URL="${BASE_URL}/linux-x64/linux-x64.zip"
PSK_DEST="$DEST_DIR/flutter_patched_sdk_product"
if [ ! -d "$PSK_DEST" ]; then
    TMP_PSK="$(mktemp -d)"
    if curl -sSLf --max-time 180 "$PSK_URL" -o "$TMP_ZIP" 2>/dev/null; then
        unzip -q -o "$TMP_ZIP" -d "$TMP_PSK" 2>/dev/null || true
        if [ -d "$TMP_PSK/flutter_patched_sdk_product" ]; then
            cp -r "$TMP_PSK/flutter_patched_sdk_product" "$PSK_DEST"
            echo "  [OK] flutter_patched_sdk_product extracted to: $PSK_DEST"
        else
            echo "  INFO: flutter_patched_sdk_product not in linux-x64.zip (will use SDK cache)"
        fi
    fi
    rm -rf "$TMP_PSK"
fi

echo ""
echo "Engine artifacts available in: $DEST_DIR"
ls -lh "$DEST_DIR"

# ── Validate: for non-armhf, libflutter_engine.so must exist ─────────────────
if [ "$ARMHF_FALLBACK" = "false" ] && [ ! -f "$DEST_DIR/libflutter_engine.so" ]; then
    echo "ERROR: libflutter_engine.so was not extracted to $DEST_DIR" >&2
    exit 1
fi

if [ "$ARMHF_FALLBACK" = "false" ] && [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    echo "ERROR: icudtl.dat was not extracted to $DEST_DIR" >&2
    exit 1
fi

echo "Engine artifact fetch complete for $ARCH."
