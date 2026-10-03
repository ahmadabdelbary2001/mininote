#!/bin/bash
# Builds flutter-embedded-linux (Wayland backend) at commit 4d95294030d703df9b3448d0db5f72adbab7416e
# for the specified target architecture.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

EMBEDDER_REV="4d95294030d703df9b3448d0db5f72adbab7416e"
SRC_DIR="$ROOT_DIR/build/flutter-embedded-linux-src"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"

echo "Building flutter-embedded-linux for $ARCH (Revision: $EMBEDDER_REV)..."

if [ ! -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    echo "Engine artifact missing at $ENGINE_DIR/libflutter_engine.so. Fetching..."
    "$ROOT_DIR/scripts/fetch-engine-artifacts.sh" "$ARCH"
fi

# Clone or checkout the required commit
if [ ! -d "$SRC_DIR" ]; then
    echo "Cloning flutter-embedded-linux repository..."
    git init -q "$SRC_DIR"
    git -C "$SRC_DIR" remote add origin https://github.com/NotKit/flutter-embedded-linux.git
    git -C "$SRC_DIR" fetch -q --depth 1 origin "$EMBEDDER_REV"
    git -C "$SRC_DIR" checkout -q FETCH_HEAD
fi

# Place libflutter_engine.so in build dir expected by embedder cmake
mkdir -p "$SRC_DIR/build"
cp "$ENGINE_DIR/libflutter_engine.so" "$SRC_DIR/build/libflutter_engine.so"

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

echo "Configuring CMake for embedder..."
cmake -S "$SRC_DIR" -B "$CMAKE_BUILD_DIR" \
    -DBUILD_ELINUX_SO=ON \
    -DBACKEND_TYPE=WAYLAND \
    -DCMAKE_BUILD_TYPE=Release \
    -DFLUTTER_RELEASE=ON \
    -DENABLE_ELINUX_EMBEDDER_LOG=OFF \
    "${EXTRA_CMAKE_ARGS[@]}"

echo "Compiling libflutter_elinux_wayland.so..."
cmake --build "$CMAKE_BUILD_DIR" --config Release --target flutter_elinux_wayland -j"$(nproc || echo 2)"

# Copy built library to engine artifacts
if [ -f "$CMAKE_BUILD_DIR/libflutter_elinux_wayland.so" ]; then
    cp "$CMAKE_BUILD_DIR/libflutter_elinux_wayland.so" "$ENGINE_DIR/libflutter_elinux_wayland.so"
    echo "libflutter_elinux_wayland.so built successfully for $ARCH and installed to $ENGINE_DIR"
else
    echo "ERROR: libflutter_elinux_wayland.so was not generated in $CMAKE_BUILD_DIR" >&2
    exit 1
fi
