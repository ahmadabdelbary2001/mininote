#!/bin/bash
# =============================================================================
# build-engine.sh — Build a RELEASE-MODE Flutter engine from source
# =============================================================================
# Why build from source?
#   The engine artifacts published on the Flutter CDN (`linux-*-embedder.zip`)
#   contain a JIT/debug engine.  Flutter's own documentation states that the
#   engine shipped for embedders "assumes that the mode of operation is JIT"
#   and is therefore incompatible with AOT snapshots.  Pairing that engine
#   with an AOT `libapp.so` aborts on the device with a snapshot/VM mismatch.
#
#   The proven fix (used by FluffyChat's Ubuntu Touch packaging) is to build
#   the engine ourselves with `--runtime-mode=release` from the exact engine
#   revision the installed Flutter SDK uses, and to use *that* build's
#   `gen_snapshot` for the AOT step.  Engine and snapshot then come from the
#   same source tree, so their Dart VM "features" strings match and the
#   snapshot loads in product mode.
#
# Produced artifacts (in build/engine-artifacts/<arch>/):
#   libflutter_engine.so   release engine for the target architecture
#   gen_snapshot           release (product mode) AOT compiler
#   icudtl.dat             ICU data (architecture independent)
#   include/flutter_embedder.h
#   engine.version         the engine revision the artifacts were built from
#
# Usage: build-engine.sh <arch> [engine_sha]
#   arch:       amd64 | arm64 | armhf (armhf is skipped: no 32-bit engine)
#   engine_sha: optional override; defaults to the SDK's engine.version
# =============================================================================
set -euo pipefail

ARCH="${1:-amd64}"
ENGINE_SHA_OVERRIDE="${2:-}"

ROOT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ENGINE_DIR="$ROOT_DIR/build/engine-artifacts/${ARCH}"
ENGINE_SRC="${ENGINE_SRC_DIR:-$ROOT_DIR/build/engine-src}"
DEPOT_TOOLS_DIR="${DEPOT_TOOLS_DIR:-$ROOT_DIR/build/depot_tools}"

# ─── Architecture mapping ─────────────────────────────────────────────────────
case "$ARCH" in
    amd64|x86_64)
        # Native x86_64 host build (out/host_release), like the official
        # linux-x64 engine artifacts.
        GN_TARGET_ARGS=""
        GN_OUT_DIR="host_release"
        EXPECTED_ENGINE_ELF="x86-64"
        HOST_ELF_PATTERN="x86-64"
        ;;
    arm64|aarch64)
        # Native aarch64 build.  The engine treats linux/arm64 as a host build
        # (see engine tools/gn: is_host_build()), so on an arm64 runner this
        # produces a native arm64 engine in out/linux_release_arm64.
        GN_TARGET_ARGS="--target-os=linux --linux-cpu=arm64"
        GN_OUT_DIR="linux_release_arm64"
        EXPECTED_ENGINE_ELF="aarch64"
        HOST_ELF_PATTERN="aarch64"
        ;;
    armhf|arm)
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
        echo "ERROR: Unsupported architecture '$ARCH' (use amd64, arm64 or armhf)" >&2
        exit 1
        ;;
esac

echo "══════════════════════════════════════════════════════════"
echo "  Building release Flutter engine for ${ARCH}"
echo "══════════════════════════════════════════════════════════"

# ─── Resolve the engine revision ─────────────────────────────────────────────
FLUTTER_ROOT=""
if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="$(command -v flutter)"
    FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$FLUTTER_BIN")")")"
fi

ENGINE_SHA="$ENGINE_SHA_OVERRIDE"
if [ -z "$ENGINE_SHA" ] && [ -n "$FLUTTER_ROOT" ]; then
    ENGINE_STAMP="$FLUTTER_ROOT/bin/internal/engine.version"
    if [ -f "$ENGINE_STAMP" ]; then
        ENGINE_SHA="$(tr -d '[:space:]' < "$ENGINE_STAMP")"
    fi
fi

if [ -z "$ENGINE_SHA" ]; then
    echo "ERROR: Could not determine the Flutter engine revision." >&2
    echo "       Pass it explicitly: $0 $ARCH <engine_sha>" >&2
    exit 1
fi

echo "  Engine revision: $ENGINE_SHA"
echo "  Output dir:      $ENGINE_DIR"

# ─── Cache check ─────────────────────────────────────────────────────────────
# The engine build takes ~30-60 minutes, so skip it when the artifacts for
# this exact revision are already present.
STAMP_FILE="$ENGINE_DIR/engine.version"
if [ -f "$ENGINE_DIR/libflutter_engine.so" ] \
   && [ -f "$ENGINE_DIR/gen_snapshot" ] \
   && [ -f "$ENGINE_DIR/icudtl.dat" ] \
   && [ -f "$STAMP_FILE" ] \
   && [ "$(tr -d '[:space:]' < "$STAMP_FILE")" = "$ENGINE_SHA" ]; then
    echo "  [OK] Release engine artifacts already present for $ENGINE_SHA — skipping build."
    exit 0
fi

mkdir -p "$ENGINE_DIR"

# ─── Toolchain checks ────────────────────────────────────────────────────────
for tool in git python3 curl; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: Required tool '$tool' not found in PATH." >&2
        exit 1
    }
done

# depot_tools provides `gclient` and `gn`.
if [ ! -d "$DEPOT_TOOLS_DIR/.git" ]; then
    echo "Cloning depot_tools..."
    rm -rf "$DEPOT_TOOLS_DIR"
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git \
        "$DEPOT_TOOLS_DIR"
fi
export PATH="$DEPOT_TOOLS_DIR:$PATH"

# ninja: prefer the system one, fall back to the copy in the engine checkout.
NINJA_BIN="$(command -v ninja || true)"

# ─── Fetch the engine source (flutter/flutter monorepo) ──────────────────────
# The engine lives in the flutter/flutter repository under engine/src/flutter.
# The DEPS file sits in the repository root since the engine was merged into
# the framework repository.
echo ""
echo "── Fetching engine source ───────────────────────────────────────────"
if [ ! -d "$ENGINE_SRC/.git" ]; then
    rm -rf "$ENGINE_SRC"
    mkdir -p "$ENGINE_SRC"
    git init -q "$ENGINE_SRC"
fi

if ! git -C "$ENGINE_SRC" remote get-url origin >/dev/null 2>&1; then
    git -C "$ENGINE_SRC" remote add origin https://github.com/flutter/flutter.git
fi

if [ "$(git -C "$ENGINE_SRC" rev-parse HEAD 2>/dev/null || echo none)" != "$ENGINE_SHA" ]; then
    echo "  Fetching flutter/flutter @ $ENGINE_SHA ..."
    git -C "$ENGINE_SRC" fetch -q --depth 1 origin "$ENGINE_SHA"
    git -C "$ENGINE_SRC" checkout -q --force FETCH_HEAD
fi
git -C "$ENGINE_SRC" rev-parse HEAD

# ─── Patch DEPS ──────────────────────────────────────────────────────────────
# The openjdk CIPD package has no linux-arm64 build, and its DEPS entry is
# unconditional, so `gclient sync` fails on an arm64 host.  The JDK is only
# needed to run the java formatter, which we do not use.
echo ""
echo "── Patching DEPS ──────────────────────────────────────────────────────"
/usr/bin/python3 - "$ENGINE_SRC/DEPS" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as handle:
    deps = handle.read()

key = "'engine/src/flutter/third_party/java/openjdk'"
if key not in deps:
    print('  [OK] openjdk DEPS entry already removed')
    sys.exit(0)

pattern = re.compile(
    r"^[ \t]*" + re.escape(key) + r":[ \t]*\{[\s\S]*?^[ \t]*\},\n",
    re.MULTILINE,
)
new_deps, count = pattern.subn('', deps)
if count != 1:
    sys.exit(f'ERROR: expected exactly 1 openjdk DEPS entry, removed {count}')

with open(path, 'w', encoding='utf-8') as handle:
    handle.write(new_deps)
print('  [OK] removed the openjdk DEPS entry')
PY

# ─── gclient configuration ──────────────────────────────────────────────────
# managed=False keeps gclient from touching our own checkout of the root
# repository; the DEPS file still drives all the third-party dependencies.
cat > "$ENGINE_SRC/.gclient" << EOF
solutions = [
  {
    "managed": False,
    "name": ".",
    "url": "https://github.com/flutter/flutter.git@${ENGINE_SHA}",
    "deps_file": "DEPS",
    "safesync_url": "",
    "custom_vars": {
      "download_android_deps": False,
      "download_emsdk": False,
      "download_fuchsia_deps": False,
    },
  },
]
EOF

echo ""
echo "── Syncing engine dependencies (gclient) ────────────────────────────"
( cd "$ENGINE_SRC" && gclient sync --no-history -D --shallow )

# ─── GN configuration ────────────────────────────────────────────────────────
# --runtime-mode=release  : release engine, product-mode Dart VM
# --no-goma               : no remote build service
# --enable-fontconfig     : resolve system fonts through fontconfig, so the
#                           app can use the device's system fonts on UT
echo ""
echo "── Configuring GN (release mode) ────────────────────────────────────"
cd "$ENGINE_SRC/engine/src/flutter"
/usr/bin/python3 tools/gn \
    --runtime-mode=release \
    --no-goma \
    --enable-fontconfig \
    $GN_TARGET_ARGS

OUT_DIR="$ENGINE_SRC/engine/src/out/$GN_OUT_DIR"
if [ ! -d "$OUT_DIR" ]; then
    echo "ERROR: GN output directory $OUT_DIR was not created." >&2
    ls -la "$ENGINE_SRC/engine/src/out" 2>/dev/null || true
    exit 1
fi

# ─── Build ───────────────────────────────────────────────────────────────────
echo ""
echo "── Building libflutter_engine.so + gen_snapshot ──────────────────────"
# Prefer the ninja that ships with the engine checkout, fall back to the
# system one.
if [ -x "$ENGINE_SRC/third_party/ninja/ninja" ]; then
    NINJA_CMD=("$ENGINE_SRC/third_party/ninja/ninja")
elif [ -n "$NINJA_BIN" ]; then
    NINJA_CMD=("$NINJA_BIN")
else
    echo "ERROR: no ninja binary found (install ninja-build)." >&2
    exit 1
fi

JOBS="$(nproc 2>/dev/null || echo 2)"
"${NINJA_CMD[@]}" -C "$OUT_DIR" -j "$JOBS" libflutter_engine.so gen_snapshot

# ─── Collect the artifacts ──────────────────────────────────────────────────
echo ""
echo "── Collecting engine artifacts ──────────────────────────────────────"

ENGINE_LIB="$OUT_DIR/libflutter_engine.so"
if [ ! -f "$ENGINE_LIB" ]; then
    echo "ERROR: libflutter_engine.so not found at $ENGINE_LIB" >&2
    exit 1
fi

cp -f "$ENGINE_LIB" "$ENGINE_DIR/libflutter_engine.so"

# gen_snapshot must run on the build host, and it must produce snapshots for
# the *target* architecture.  Prefer the default toolchain binary; fall back to
# the host ("clang_x64") toolchain when the default one targets another arch.
GEN_SNAPSHOT_SRC=""
for candidate in \
    "$OUT_DIR/gen_snapshot" \
    "$OUT_DIR/clang_x64/gen_snapshot" \
    "$OUT_DIR/host/gen_snapshot"; do
    if [ -x "$candidate" ] && file "$candidate" | grep -q "$HOST_ELF_PATTERN"; then
        GEN_SNAPSHOT_SRC="$candidate"
        break
    fi
done

if [ -z "$GEN_SNAPSHOT_SRC" ]; then
    echo "ERROR: no host-runnable gen_snapshot found under $OUT_DIR" >&2
    find "$OUT_DIR" -name gen_snapshot -type f | head -10 >&2
    exit 1
fi
echo "  gen_snapshot: $GEN_SNAPSHOT_SRC"
cp -f "$GEN_SNAPSHOT_SRC" "$ENGINE_DIR/gen_snapshot"
chmod +x "$ENGINE_DIR/gen_snapshot"

# icudtl.dat: generated by the engine build, otherwise taken from the Flutter
# SDK cache (same engine revision, so the ICU version matches).
ICU_SRC="$ENGINE_SRC/engine/src/flutter/third_party/icu/flutter/icudtl.dat"
if [ ! -f "$ICU_SRC" ]; then
    # The ICU data is a separate GN target; build it explicitly.
    echo "  icudtl.dat not built yet, building the icudtl target..."
    "${NINJA_CMD[@]}" -C "$OUT_DIR" -j "$JOBS" icudtl || true
fi

if [ -f "$ICU_SRC" ]; then
    cp -f "$ICU_SRC" "$ENGINE_DIR/icudtl.dat"
    echo "  icudtl.dat:   $ICU_SRC"
elif [ -n "$FLUTTER_ROOT" ] && [ -f "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/icudtl.dat" ]; then
    cp -f "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-x64/icudtl.dat" "$ENGINE_DIR/icudtl.dat"
    echo "  icudtl.dat:   (from the Flutter SDK cache)"
else
    echo "ERROR: icudtl.dat not found — the engine cannot start without it." >&2
    exit 1
fi

# The embedder API header (not required to build, but handy for reference and
# used by the packaging validation).
EMBEDDER_HEADER="$ENGINE_SRC/engine/src/flutter/shell/platform/embedder/embedder.h"
if [ -f "$EMBEDDER_HEADER" ]; then
    mkdir -p "$ENGINE_DIR/include"
    cp -f "$EMBEDDER_HEADER" "$ENGINE_DIR/include/flutter_embedder.h"
fi

printf '%s\n' "$ENGINE_SHA" > "$STAMP_FILE"

# ─── Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "── Verifying engine artifacts ────────────────────────────────────────"
ls -lh "$ENGINE_DIR"
file "$ENGINE_DIR/libflutter_engine.so"
file "$ENGINE_DIR/gen_snapshot"

if ! file "$ENGINE_DIR/libflutter_engine.so" | grep -q "$EXPECTED_ENGINE_ELF"; then
    echo "ERROR: libflutter_engine.so is not a $EXPECTED_ENGINE_ELF binary!" >&2
    exit 1
fi

# The engine has no RPATH of its own; the bundle ships every library next to
# it, so $ORIGIN is what the loader must use.
if command -v patchelf >/dev/null 2>&1; then
    patchelf --set-rpath '$ORIGIN' "$ENGINE_DIR/libflutter_engine.so" || true
    echo "  RPATH set to \$ORIGIN on libflutter_engine.so"
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Release engine ready: $ENGINE_DIR (revision $ENGINE_SHA)"
echo "══════════════════════════════════════════════════════════"
