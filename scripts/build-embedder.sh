#!/bin/bash
# Builds flutter-embedded-linux (Wayland backend) for the specified target architecture.
#
# Commit: 4d95294030d703df9b3448d0db5f72adbab7416e  (NotKit/flutter-embedded-linux)
#
# The embedder links against the *release* Flutter engine produced by
# scripts/build-engine.sh.  The engine published on the Flutter CDN is a
# JIT/debug build and cannot load an AOT snapshot, so it must not be used
# here.
#
# Maliit note: the embedder includes <maliit-glib/maliitbus.h> unconditionally
# (on-screen keyboard support), so the maliit-glib development files have to
# be installed (libmaliit-glib-dev, available in Ubuntu 24.04 universe).  The
# CMake dependency is downgraded from REQUIRED to optional so that a missing
# package produces a clear compile error instead of a hard CMake failure.
set -euo pipefail

ARCH="${1:-amd64}"
ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

EMBEDDER_REV="4d95294030d703df9b3448d0db5f72adbab7416e"
SRC_DIR="$ROOT_DIR/build/flutter-embedded-linux-src"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"

echo "Building flutter-embedded-linux for $ARCH (Revision: $EMBEDDER_REV)..."

# ── Ensure the release engine is present ─────────────────────────────────
if [ ! -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    echo "Release engine missing at $ENGINE_DIR/libflutter_engine.so. Building it..."
    "$ROOT_DIR/scripts/build-engine.sh" "$ARCH"
fi

if [ ! -f "$ENGINE_DIR/libflutter_engine.so" ]; then
    echo "ERROR: libflutter_engine.so still missing — cannot build embedder for $ARCH" >&2
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

# ── Patch: make maliit-glib optional (not available in every rootfs) ─────
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

# The on-screen keyboard plugin includes the maliit-glib headers directly, so
# the development package is mandatory for the build to succeed.
if ! pkg-config --exists maliit-glib 2>/dev/null; then
    echo "ERROR: maliit-glib development files are required by the eLinux embedder." >&2
    echo "       Install them with: sudo apt-get install libmaliit-glib-dev" >&2
    exit 1
fi

# The content-hub clipboard support of this embedder revision needs GIO.
if ! pkg-config --exists gio-2.0 2>/dev/null; then
    echo "ERROR: gio-2.0 development files are required by the eLinux embedder." >&2
    echo "       Install them with: sudo apt-get install libglib2.0-dev" >&2
    exit 1
fi

# ── Patch: Add missing <cstdint> includes for Clang 18 / GCC 13+ ──────────
BM_HEADER="$SRC_DIR/src/flutter/shell/platform/common/client_wrapper/include/flutter/binary_messenger.h"
if [ -f "$BM_HEADER" ] && ! grep -q '<cstdint>' "$BM_HEADER"; then
    echo "Patching binary_messenger.h: adding #include <cstdint>..."
    sed -i 's/#include <functional>/#include <functional>\n#include <cstdint>/' "$BM_HEADER"
fi

LC_HEADER="$SRC_DIR/src/flutter/shell/platform/linux_embedded/plugins/lifecycle_plugin.h"
if [ -f "$LC_HEADER" ] && ! grep -q '<cstdint>' "$LC_HEADER"; then
    echo "Patching lifecycle_plugin.h: adding #include <cstdint>..."
    sed -i 's/#include <string>/#include <string>\n#include <cstdint>/' "$LC_HEADER"
fi

LC_CC="$SRC_DIR/src/flutter/shell/platform/linux_embedded/plugins/lifecycle_plugin.cc"
if [ -f "$LC_CC" ] && ! grep -q '<cstdint>' "$LC_CC"; then
    echo "Patching lifecycle_plugin.cc: adding #include <cstdint>..."
    sed -i '1i #include <cstdint>' "$LC_CC"
fi

# ── Place libflutter_engine.so where CMake expects it ─────────────────────
mkdir -p "$SRC_DIR/build"
cp "$ENGINE_DIR/libflutter_engine.so" "$SRC_DIR/build/libflutter_engine.so"

# ── Export architecture triplet for clang target selection in CMakeLists ───
case "$ARCH" in
    arm64)
        export ARCH_TRIPLET="aarch64-linux-gnu"
        ;;
    amd64)
        export ARCH_TRIPLET="x86_64-linux-gnu"
        ;;
    armhf)
        export ARCH_TRIPLET="arm-linux-gnueabihf"
        ;;
esac

# Ensure maliit-glib header paths are accessible for all include formats
if [ -d "/usr/include/maliit-2/maliit-glib" ] && [ ! -d "/usr/include/maliit-glib" ]; then
    sudo ln -sf /usr/include/maliit-2/maliit-glib /usr/include/maliit-glib 2>/dev/null || true
fi

MALIIT_INCLUDES=""
if [ -d "/usr/include/maliit-2" ]; then
    MALIIT_INCLUDES="-I/usr/include/maliit-2 -I/usr/include/maliit-2/maliit-glib"
fi

GLOBAL_CXX_FLAGS="-include cstdint ${MALIIT_INCLUDES}"
GLOBAL_C_FLAGS="-include stdint.h ${MALIIT_INCLUDES}"

# ── Configure CMake cross-compilation flags ────────────────────────────────
CMAKE_BUILD_DIR="$ROOT_DIR/build/embedder-build-${ARCH}"
rm -rf "$CMAKE_BUILD_DIR"
mkdir -p "$CMAKE_BUILD_DIR"

# Native builds (the CI uses a native runner per architecture) must not use
# the cross-compilation flags, they would break the host toolchain.
HOST_MACHINE="$(uname -m)"
NATIVE_BUILD=false
case "${ARCH}:${HOST_MACHINE}" in
    amd64:x86_64|arm64:aarch64|arm64:arm64) NATIVE_BUILD=true ;;
esac

EXTRA_CMAKE_ARGS=()
if [ "$ARCH" = "arm64" ] && [ "$NATIVE_BUILD" = "false" ]; then
    # Cross build from an x86_64 host.
    export PKG_CONFIG_PATH="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"
    EXTRA_CMAKE_ARGS+=(
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSTEM_PROCESSOR=aarch64"
        "-DCMAKE_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu"
        "-DCMAKE_CXX_FLAGS=${GLOBAL_CXX_FLAGS}"
        "-DCMAKE_C_FLAGS=${GLOBAL_C_FLAGS}"
    )
elif [ "$ARCH" = "amd64" ] || { [ "$ARCH" = "arm64" ] && [ "$NATIVE_BUILD" = "true" ]; }; then
    EXTRA_CMAKE_ARGS+=(
        "-DCMAKE_CXX_FLAGS=${GLOBAL_CXX_FLAGS}"
        "-DCMAKE_C_FLAGS=${GLOBAL_C_FLAGS}"
    )
elif [ "$ARCH" = "armhf" ]; then
    EXTRA_CMAKE_ARGS+=(
        "-DCMAKE_SYSTEM_NAME=Linux"
        "-DCMAKE_SYSTEM_PROCESSOR=arm"
        "-DCMAKE_CXX_FLAGS=${GLOBAL_CXX_FLAGS} -I/usr/arm-linux-gnueabihf/include/c++/9/arm-linux-gnueabihf"
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
    # The embedder is built with CMAKE_SKIP_RPATH, so give it an $ORIGIN RPATH
    # to find libflutter_engine.so next to it inside the Click bundle.
    if command -v patchelf >/dev/null 2>&1; then
        patchelf --set-rpath '$ORIGIN' "$ENGINE_DIR/libflutter_elinux_wayland.so" || true
    fi
    echo "libflutter_elinux_wayland.so built successfully for $ARCH → $ENGINE_DIR"
else
    echo "ERROR: libflutter_elinux_wayland.so was not generated in $CMAKE_BUILD_DIR" >&2
    exit 1
fi
