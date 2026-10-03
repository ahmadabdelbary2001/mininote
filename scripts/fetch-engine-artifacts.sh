#!/bin/bash
# Fetches matching Flutter Engine artifacts (libflutter_engine.so, icudtl.dat, headers)
# from official Flutter infrastructure for the target architecture.
#
# armhf note: Flutter's CDN stopped shipping pre-built linux-arm (32-bit) engine
# binaries for Flutter ≥ 3.10.  For armhf we attempt a best-effort download;
# if the CDN returns 404 the script exits 0 with a warning so that the armhf
# CI job can be marked continue-on-error rather than hard-failing the pipeline.
set -euo pipefail

ARCH="${1:-}"
ENGINE_SHA="${2:-}"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <arch> [engine_sha]" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

# ── Resolve Engine SHA ────────────────────────────────────────────────────
if [ -z "$ENGINE_SHA" ]; then
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER_BIN="$(which flutter)"
        FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"
        ENGINE_STAMP="$FLUTTER_ROOT/bin/internal/engine.version"
        if [ -f "$ENGINE_STAMP" ]; then
            ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_STAMP")"
        fi
    fi
fi

if [ -z "$ENGINE_SHA" ]; then
    # Fallback: Flutter 3.41.7 engine hash
    ENGINE_SHA="59aa584fdf100e6c78c785d8a5b565d1de4b48ab"
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
        # 32-bit ARM engine is NOT published on the CDN for Flutter >= 3.10.
        # We attempt the download and warn gracefully on 404.
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

# ── 1. Download Embedder zip ──────────────────────────────────────────────
EMBEDDER_ZIP_URL="${BASE_URL}/${FLUTTER_TARGET}/${FLUTTER_TARGET}-embedder.zip"
echo "Downloading embedder from: $EMBEDDER_ZIP_URL"
if curl -sSLf "$EMBEDDER_ZIP_URL" -o "$TMP_ZIP"; then
    echo "Extracting embedder artifacts..."
    unzip -q -o "$TMP_ZIP" -d "$DEST_DIR"
else
    if [ "$ARMHF_FALLBACK" = "true" ]; then
        echo "WARNING: armhf embedder zip not found on CDN (Flutter dropped arm32 support)."
        echo "         armhf build will be skipped — this is expected for Flutter >= 3.10."
        # Still try to get icudtl.dat from linux-x64 so the partial cache is useful
    else
        echo "Embedder zip not found at $EMBEDDER_ZIP_URL" >&2
        exit 1
    fi
fi

# ── 2. Download icudtl.dat if not present ─────────────────────────────────
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    ICU_URL="${BASE_URL}/${FLUTTER_TARGET}/artifacts.zip"
    echo "Checking ${FLUTTER_TARGET}/artifacts.zip for icudtl.dat..."
    if curl -sSLf "$ICU_URL" -o "$TMP_ZIP" 2>/dev/null; then
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" 2>/dev/null || true
    fi
fi

# Final fallback: linux-x64 always has icudtl.dat (architecture-independent data)
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    echo "Fetching icudtl.dat from linux-x64 artifacts (universal fallback)..."
    if curl -sSLf "${BASE_URL}/linux-x64/artifacts.zip" -o "$TMP_ZIP"; then
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" 2>/dev/null || true
    fi
fi

echo "Engine artifacts available in: $DEST_DIR"
ls -lh "$DEST_DIR"

# ── 3. Validate: for non-armhf, libflutter_engine.so must exist ──────────
if [ "$ARMHF_FALLBACK" = "false" ] && [ ! -f "$DEST_DIR/libflutter_engine.so" ]; then
    echo "ERROR: libflutter_engine.so was not extracted to $DEST_DIR" >&2
    exit 1
fi
