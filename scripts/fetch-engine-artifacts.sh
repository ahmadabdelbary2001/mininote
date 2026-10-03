#!/bin/bash
# Fetches matching Flutter Engine artifacts (libflutter_engine.so, icudtl.dat, headers)
# from official Flutter infrastructure for the target architecture.
set -euo pipefail

ARCH="${1:-}"
ENGINE_SHA="${2:-}"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <arch> [engine_sha]" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

# Resolve Engine SHA
if [ -z "$ENGINE_SHA" ]; then
    if command -v flutter >/dev/null 2>&1; then
        FLUTTER_BIN="$(which flutter)"
        FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"
        if [ -f "$FLUTTER_ROOT/bin/internal/engine.version" ]; then
            ENGINE_SHA="$(tr -d '[:space:]' < "$FLUTTER_ROOT/bin/internal/engine.version")"
        fi
    fi
fi

if [ -z "$ENGINE_SHA" ]; then
    # Fallback to current repository known Flutter 3.41.7 engine hash
    ENGINE_SHA="7a53c052bc4b472cf780b199087e1368e4a9aa8c"
fi

echo "Fetching engine artifacts for $ARCH (Engine SHA: $ENGINE_SHA)..."

case "$ARCH" in
    amd64|x86_64)
        FLUTTER_TARGET="linux-x64"
        ;;
    arm64|aarch64)
        FLUTTER_TARGET="linux-arm64"
        ;;
    armhf|arm)
        echo "Notice: 32-bit ARM engine requires custom/patched build or community elinux engine cache."
        FLUTTER_TARGET="linux-arm"
        ;;
    *)
        echo "ERROR: Unknown architecture $ARCH" >&2
        exit 1
        ;;
esac

DEST_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"
mkdir -p "$DEST_DIR"

BASE_URL="https://storage.googleapis.com/flutter_infra_release/flutter/${ENGINE_SHA}"

# 1. Download Embedder zip
EMBEDDER_ZIP_URL="${BASE_URL}/${FLUTTER_TARGET}/${FLUTTER_TARGET}-embedder.zip"
TMP_ZIP="$(mktemp --suffix=.zip)"

echo "Downloading embedder from: $EMBEDDER_ZIP_URL"
if curl -sSLf "$EMBEDDER_ZIP_URL" -o "$TMP_ZIP"; then
    echo "Extracting embedder artifacts..."
    unzip -q -o "$TMP_ZIP" -d "$DEST_DIR"
    rm -f "$TMP_ZIP"
else
    echo "Embedder zip not found directly on CDN at $EMBEDDER_ZIP_URL"
fi

# 2. Download icudtl.dat if not present in embedder zip
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    ICU_URL="${BASE_URL}/${FLUTTER_TARGET}/artifacts.zip"
    echo "Checking artifacts.zip for icudtl.dat..."
    if curl -sSLf "$ICU_URL" -o "$TMP_ZIP"; then
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" 2>/dev/null || true
        rm -f "$TMP_ZIP"
    fi
fi

# If icudtl.dat is still missing, fetch from generic linux-x64
if [ ! -f "$DEST_DIR/icudtl.dat" ]; then
    echo "Fetching icudtl.dat from linux-x64 artifacts..."
    curl -sSLf "${BASE_URL}/linux-x64/artifacts.zip" -o "$TMP_ZIP" && \
        unzip -q -o "$TMP_ZIP" icudtl.dat -d "$DEST_DIR" && \
        rm -f "$TMP_ZIP"
fi

echo "Engine artifacts available in: $DEST_DIR"
ls -lh "$DEST_DIR"
