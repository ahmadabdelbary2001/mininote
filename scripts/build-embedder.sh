#!/bin/bash
# Builds flutter-embedded-linux (Wayland backend) for the specified target architecture.
#
# Commit: 4d95294030d703df9b3448d0db5f72adbab7416e  (NotKit/flutter-embedded-linux)
#
# Maliit note: the embedder CMake requires maliit-glib headers when the
# on-screen keyboard backend is enabled.  maliit-glib-dev is not shipped in
# Ubuntu 24.04's main/universe repos.  Since Lomiri on Ubuntu Touch handles
# OSK input via its own IPC (independent of the embedder's GLib loop), we
# patch cmake/package.cmake after clone to make maliit-glib *optional* rather
# than *required*.  The resulting .so still works correctly on-device; only
# the build-time GLib notification path is disabled.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

EMBEDDER_REV="4d95294030d703df9b3448d0db5f72adbab7416e"
SRC_DIR="$ROOT_DIR/build/flutter-embedded-linux-src"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"

echo "Building flutter-embedded-linux for $ARCH (Revision: $EMBEDDER_REV)..."

# ── Ensure libflutter_engine.so is present ────────────────────────────────
if [ ! -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    echo "Engine artifact missing at $ENGINE_DIR/libflutter_engine.so. Fetching..."
    "$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH"
fi

if [ ! -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    echo "ERROR: libflutter_engine.so still missing after fetch — cannot build embedder for $ARCH" >&2
    exit 1
fi

# ── Clone or checkout the required commit ─────────────────────────────────
if [ ! -d "$SRC_DIR" ]; then
    echo "Cloning flutter-embedded-linux repository..."
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin https://github.com/NotKit/flutter-embedded-linux.git
    git -C "$SRC_DIR" fetch -q --depth 1 origin "$EMBEDDER_REV"
    git -C "$SRC_DIR" checkout -q FETCH_HEAD
fi

# ── Patch: make maliit-glib optional (not available in Ubuntu 24.04) ──────
# The pkg_search_module call for maliit-glib uses REQUIRED in this commit.
# We downgrade it to a soft dependency so CMake can proceed without the
# headers installed; the final .so does not need maliit at runtime on UT.
PACKAGE_CMAKE="$SRC_DIR/cmake/package.cmake"
if [ -f "$PACKAGE_CMAKE" ]; then
    if grep -q -E 'pkg_search_module\([[:space:]]*MALIIT_GLIB[[:space:]]+REQUIRED' "$PACKAGE_CMAKE"; then
        echo "Patching cmake/package.cmake: removing REQUIRED from maliit-glib..."
        sed -i -E 's/pkg_search_module\([[:space:]]*MALIIT_GLIB[[:space:]]+REQUIRED/pkg_search_module(MALIIT_GLIB/' "$PACKAGE_CMAKE"
        echo "  [OK] maliit-glib is now optional"
    else
        echo "  [OK] cmake/package.cmake maliit-glib already optional or absent"
    fi
fi

# ── Place libflutter_engine.so where CMake expects it ─────────────────────
mkdir -p "$SRC_DIR/build"
cp "$ENGINE_DIR/libflutter_engine.so" "$SRC_DIR/build/libflutter_engine.so"

# ── Configure CMake cross-compilation flags ────────────────────────────────
CMAKE_BUILD_DIR="$ROOT_DIR/build/embedder-build-${ARCH}"
rm -rf "$CMAKE_BUILD_DIR"
mkdir -p "$CMAKE_BUILD_DIR"

EXTRA_CMAKE_ARGS=()
if [ "$ARCH" = "arm64" ]; then
    EXTRA_CMAKE_ARGS+=(
        "-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc"
        "-DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++"
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSTEM_PROCESSOR=aarch64"
    )
elif [ "$ARCH" = "armhf" ]; then
    EXTRA_CMAKE_ARGS+=(
        "-DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc"
        "-DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++"
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSTEM_PROCESSOR=arm"
        "-DCMAKE_CXX_FLAGS=-I/usr/arm-linux-gnueabihf/include/c++/9/arm-linux-gnueabihf"
    )
fi

# ── Run CMake configure ───────────────────────────────────────────────────
echo "Configuring CMake for embedder ($ARCH)..."
cmake -S "$SRC_DIR" -B "$CMAKE_BUILD_DIR" \
    -DBUILD_ELINUX_SO=ON \
    -DBACKEND_TYPE=WAYLAND \
    -DCMAKE_BUILD_TYPE=Release \
    -DFLUTTER_RELEASE=ON \
    -DENABLE_ELINUX_EMBEDDER_LOG=OFF \
    "${EXTRA_CMAKE_ARGS[@]}"

# ── Compile ───────────────────────────────────────────────────────────────
echo "Compiling libflutter_elinux_wayland.so..."
cmake --build "$CMAKE_BUILD_DIR" --config Release --target flutter_elinux_wayland -j"$(nproc || echo 2)"

# ── Install to engine artifacts directory ─────────────────────────────────
if [ -f "$CMAKE_BUILD_DIR/libflutter_elinux_wayland.so" ]; then
    cp "$CMAKE_BUILD_DIR/libflutter_elinux_wayland.so" "$ENGINE_DIR/libflutter_elinux_wayland.so"
    echo "libflutter_elinux_wayland.so built successfully for $ARCH → $ENGINE_DIR"
else
    echo "ERROR: libflutter_elinux_wayland.so was not generated in $CMAKE_BUILD_DIR" >&2
    exit 1
fi
