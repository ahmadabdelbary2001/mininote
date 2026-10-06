#!/bin/bash
# Assembles the Click bundle for MiniNotes on Ubuntu Touch, validates ELF architecture,
# and generates the final .click package.
set -euo pipefail

ARCH="${1:-}"
VERSION="${2:-}"

if [ -z "$ARCH" ]; then
    echo "Usage: $0 <arch> [version]" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

if [ -z "$VERSION" ]; then
    # Strip the build-number suffix (+N) and any trailing whitespace
    VERSION="$(grep -m1 '^version:' "$ROOT_DIR/flutter_app/pubspec.yaml" \
        | sed -E 's/^version:[[:space:]]*//; s/\+[0-9]+//; s/[[:space:]]*$//')"
fi

echo "Packaging MiniNotes v${VERSION} for ${ARCH}..."

BUNDLE_DIR="$ROOT_DIR/build/click_bundle_${ARCH}"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/lib" "$BUNDLE_DIR/data" "$BUNDLE_DIR/assets/icons"

# 1. Copy Flutter assets and ICU data
ELINUX_BUNDLE="$ROOT_DIR/flutter_app/build/elinux/${ARCH}/release/bundle"
if [ ! -d "$ELINUX_BUNDLE" ]; then
    # Check alternative architecture naming (e.g. x64, arm64, arm)
    ALT_ARCH="$ARCH"
    [ "$ARCH" = "amd64" ] && ALT_ARCH="x64"
    [ "$ARCH" = "armhf" ] && ALT_ARCH="arm"
    ELINUX_BUNDLE="$ROOT_DIR/flutter_app/build/elinux/${ALT_ARCH}/release/bundle"
fi

if [ -d "$ELINUX_BUNDLE" ]; then
    echo "Copying Flutter bundle from $ELINUX_BUNDLE..."
    cp -r "$ELINUX_BUNDLE/data" "$BUNDLE_DIR/"
    # Copy AOT library (libapp.so) and any other native libs from the elinux bundle
    if [ -d "$ELINUX_BUNDLE/lib" ]; then
        cp -a "$ELINUX_BUNDLE/lib/"*.so "$BUNDLE_DIR/lib/" 2>/dev/null || true
    fi
elif [ -d "$ROOT_DIR/flutter_app/build/flutter_assets" ]; then
    # Fallback: use flutter_assets from standard `flutter build bundle` output
    echo "Falling back to flutter_app/build/flutter_assets..."
    mkdir -p "$BUNDLE_DIR/data"
    cp -r "$ROOT_DIR/flutter_app/build/flutter_assets" "$BUNDLE_DIR/data/"
fi

# Fallback/explicit ICU and Assets check
if [ ! -f "$BUNDLE_DIR/data/icudtl.dat" ] && [ -f "$ROOT_DIR/build/engine-artifacts/${ARCH}/icudtl.dat" ]; then
    cp "$ROOT_DIR/build/engine-artifacts/${ARCH}/icudtl.dat" "$BUNDLE_DIR/data/icudtl.dat"
fi

# 2. Copy Rust Runner binary (mininote)
RUNNER_TARGET="$ARCH"
case "$ARCH" in
    amd64) RUST_TARGET="x86_64-unknown-linux-gnu" ;;
    arm64) RUST_TARGET="aarch64-unknown-linux-gnu" ;;
    armhf) RUST_TARGET="armv7-unknown-linux-gnueabihf" ;;
    *) RUST_TARGET="" ;;
esac

RUNNER_BIN=""
CANDIDATES=(
    "$ROOT_DIR/flutter_app/elinux/runner/target/${RUST_TARGET}/release/mininote"
    "$ROOT_DIR/flutter_app/elinux/runner/target/release/mininote"
    "$ROOT_DIR/target/${RUST_TARGET}/release/mininote"
    "$ROOT_DIR/target/release/mininote"
)
for c in "${CANDIDATES[@]}"; do
    if [ -f "$c" ]; then
        RUNNER_BIN="$c"
        break
    fi
done

if [ -z "$RUNNER_BIN" ]; then
    echo "ERROR: Compiled Rust runner binary (mininote) not found!" >&2
    exit 1
fi
echo "Using Rust runner binary: $RUNNER_BIN"
cp "$RUNNER_BIN" "$BUNDLE_DIR/mininote"
chmod +x "$BUNDLE_DIR/mininote"

# 3. Copy Rust native_core.so
NATIVE_CORE_SO=""
CORE_CANDIDATES=(
    "$ROOT_DIR/native_core/target/${RUST_TARGET}/release/libnative_core.so"
    "$ROOT_DIR/native_core/target/release/libnative_core.so"
    "$ROOT_DIR/target/${RUST_TARGET}/release/libnative_core.so"
    "$ROOT_DIR/target/release/libnative_core.so"
)
for c in "${CORE_CANDIDATES[@]}"; do
    if [ -f "$c" ]; then
        NATIVE_CORE_SO="$c"
        break
    fi
done

if [ -z "$NATIVE_CORE_SO" ]; then
    echo "ERROR: Compiled libnative_core.so not found!" >&2
    exit 1
fi
echo "Using native_core.so: $NATIVE_CORE_SO"
cp "$NATIVE_CORE_SO" "$BUNDLE_DIR/lib/libnative_core.so"
cp "$NATIVE_CORE_SO" "$BUNDLE_DIR/libnative_core.so"

# 4. Copy flutter engine and embedder shared libraries
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"
if [ -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    cp "$ENGINE_DIR/libflutter_engine.so" "$BUNDLE_DIR/lib/libflutter_engine.so"
fi
if [ -f "$ENGINE_DIR/libflutter_elinux_wayland.so" ]; then
    cp "$ENGINE_DIR/libflutter_elinux_wayland.so" "$BUNDLE_DIR/lib/libflutter_elinux_wayland.so"
fi

# 5. Copy wrapper script, apparmor, desktop file, icon, and manifest
cp "$ROOT_DIR/packaging/click/mininote-wrapper" "$BUNDLE_DIR/mininote-wrapper"
chmod +x "$BUNDLE_DIR/mininote-wrapper"

cp "$ROOT_DIR/packaging/click/mininotes.apparmor" "$BUNDLE_DIR/mininotes.apparmor"
cp "$ROOT_DIR/packaging/click/mininotes.desktop"  "$BUNDLE_DIR/mininotes.desktop"
if [ -f "$ROOT_DIR/assets/icons/mininotes.svg" ]; then
    cp "$ROOT_DIR/assets/icons/mininotes.svg" "$BUNDLE_DIR/assets/icons/mininotes.svg"
fi

# Substitute architecture and version into manifest.json
sed -e "s/ARCH_PLACEHOLDER/${ARCH}/g" \
    -e "s/\"version\": \".*\"/\"version\": \"${VERSION}\"/g" \
    "$ROOT_DIR/packaging/click/manifest.json" > "$BUNDLE_DIR/manifest.json"

# 6. Run validation on the assembled bundle
"$ROOT_DIR/scripts/validate-click.sh" "$BUNDLE_DIR" "$ARCH"

# 7. Package using click tool
mkdir -p "$ROOT_DIR/dist"
echo "Running click build for $ARCH..."
# click build outputs the .click file to the current directory.
# We change to $ROOT_DIR/dist so the file lands there directly.
(
    cd "$ROOT_DIR/dist"
    click build "$BUNDLE_DIR"
)

FINAL_NAME="$ROOT_DIR/dist/mininotes_${VERSION}_${ARCH}.click"
# Normalise whatever click produced to the canonical name
GENERATED="$(find "$ROOT_DIR/dist" -name '*.click' -newer "$BUNDLE_DIR" | head -1)"
if [ -n "$GENERATED" ] && [ "$GENERATED" != "$FINAL_NAME" ]; then
    mv "$GENERATED" "$FINAL_NAME"
fi
if [ -f "$FINAL_NAME" ]; then
    echo "Click package successfully built at: $FINAL_NAME"
else
    echo "ERROR: Expected click package not found at $FINAL_NAME" >&2
    ls -lh "$ROOT_DIR/dist/"
    exit 1
fi
