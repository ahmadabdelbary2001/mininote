#!/bin/bash
# Validation script for MiniNotes Ubuntu Touch Click package and bundle.
# Fails immediately if any binary is missing, fake, or has an architecture mismatch.
set -euo pipefail

BUNDLE_DIR="${1:-build/click_bundle}"
EXPECTED_ARCH="${2:-}"

if [ -z "$EXPECTED_ARCH" ]; then
    echo "ERROR: Expected architecture (amd64, arm64, armhf) must be provided." >&2
    echo "Usage: $0 <bundle_dir> <architecture>" >&2
    exit 1
fi

echo "=========================================================="
echo "== Validating MiniNotes Bundle at: $BUNDLE_DIR"
echo "== Expected Architecture: $EXPECTED_ARCH"
echo "=========================================================="

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "ERROR: Bundle directory $BUNDLE_DIR does not exist!" >&2
    exit 1
fi

# 1. Essential files check
required_files=(
    "manifest.json"
    "mininotes.apparmor"
    "mininotes.desktop"
    "mininote-wrapper"
    "mininote"
    "lib/libflutter_engine.so"
    "lib/libflutter_elinux_wayland.so"
    "lib/libnative_core.so"
    "data/icudtl.dat"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$BUNDLE_DIR/$file" ]; then
        echo "ERROR: Required file $BUNDLE_DIR/$file is missing!" >&2
        exit 1
    fi
    echo "  [OK] Found $file"
done

# Check flutter_assets directory
if [ ! -d "$BUNDLE_DIR/data/flutter_assets" ]; then
    echo "ERROR: data/flutter_assets directory is missing!" >&2
    exit 1
fi
echo "  [OK] Found data/flutter_assets"

# 2. Check mininote executable permissions
if [ ! -x "$BUNDLE_DIR/mininote" ]; then
    echo "ERROR: mininote is not executable!" >&2
    exit 1
fi
if [ ! -x "$BUNDLE_DIR/mininote-wrapper" ]; then
    echo "ERROR: mininote-wrapper is not executable!" >&2
    exit 1
fi

# 3. Check for fake / stub scripts
if file "$BUNDLE_DIR/mininote" | grep -qi "shell script"; then
    echo "CRITICAL ERROR: mininote is a shell script instead of a real compiled ELF binary!" >&2
    cat "$BUNDLE_DIR/mininote"
    exit 1
fi

if grep -q "exec true" "$BUNDLE_DIR/mininote" 2>/dev/null; then
    echo "CRITICAL ERROR: mininote contains dummy 'exec true'!" >&2
    exit 1
fi

# 4. Architecture verification using file and readelf
check_elf_arch() {
    local target_file="$1"
    local file_output
    file_output="$(file -b "$target_file")"
    echo "Inspecting ELF: $target_file -> $file_output"

    case "$EXPECTED_ARCH" in
        amd64|x86_64)
            if ! echo "$file_output" | grep -q "x86-64"; then
                echo "CRITICAL ERROR: $target_file is NOT x86-64 ELF! Got: $file_output" >&2
                exit 1
            fi
            ;;
        arm64|aarch64)
            if ! echo "$file_output" | grep -qi -E "(aarch64|arm64)"; then
                echo "CRITICAL ERROR: $target_file is NOT aarch64 ELF! Got: $file_output" >&2
                exit 1
            fi
            ;;
        armhf|arm)
            if ! echo "$file_output" | grep -qi -E "(ARM|32-bit)"; then
                echo "CRITICAL ERROR: $target_file is NOT 32-bit ARM ELF! Got: $file_output" >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Unknown architecture $EXPECTED_ARCH" >&2
            exit 1
            ;;
    esac
}

check_elf_arch "$BUNDLE_DIR/mininote"
check_elf_arch "$BUNDLE_DIR/lib/libflutter_engine.so"
check_elf_arch "$BUNDLE_DIR/lib/libflutter_elinux_wayland.so"
check_elf_arch "$BUNDLE_DIR/lib/libnative_core.so"
if [ -f "$BUNDLE_DIR/lib/libapp.so" ]; then
    check_elf_arch "$BUNDLE_DIR/lib/libapp.so"
fi

# 5. Check RPATH/RUNPATH using readelf if readelf is present
if command -v readelf >/dev/null 2>&1; then
    echo "Verifying RPATH/RUNPATH on mininote executable..."
    if ! readelf -d "$BUNDLE_DIR/mininote" | grep -qi -E "(RPATH|RUNPATH)"; then
        echo "WARNING: mininote has no explicit RPATH/RUNPATH; mininote-wrapper will use LD_LIBRARY_PATH"
    fi
fi

# 6. Validate manifest.json architecture
MANIFEST_ARCH="$(python3 -c "import json; print(json.load(open('$BUNDLE_DIR/manifest.json'))['architecture'])")"
if [ "$MANIFEST_ARCH" != "$EXPECTED_ARCH" ]; then
    echo "ERROR: manifest.json architecture ($MANIFEST_ARCH) does not match expected ($EXPECTED_ARCH)!" >&2
    exit 1
fi
echo "  [OK] manifest.json architecture matches $EXPECTED_ARCH"

echo "=========================================================="
echo "== SUCCESS: All validation checks passed for $EXPECTED_ARCH"
echo "=========================================================="
