#!/usr/bin/env python3
"""Validate that an AOT snapshot (libapp.so) was produced in product mode.

The Dart VM embeds a "features string" in every snapshot it creates, e.g.

    product no-code_comments no-asan no-msan ... x64 linux no-compressed-pointers

The first token tells the VM which mode the snapshot was compiled in:

  * "product"  – release/product build, the only mode a release engine accepts
  * "release"  – release build without the product defines (asserts enabled)
  * "debug"    – debug build

The engine refuses to load a snapshot whose features string does not match its
own, which is why the engine and gen_snapshot have to come from the very same
release build.  A snapshot that carries "no-dedup_instructions" was not built
in product mode either.

Usage: check-aot-features.py <libapp.so> <arch>
   arch: amd64 | arm64
"""

import re
import sys

# The Dart VM uses its own names for the target architectures.
ARCH_TOKENS = {
    "amd64": ("x64", "amd64", "x86_64"),
    "arm64": ("arm64", "aarch64"),
}


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    path = sys.argv[1]
    arch = sys.argv[2]
    expected_tokens = ARCH_TOKENS.get(arch)
    if expected_tokens is None:
        print(f"ERROR: unknown architecture '{arch}'", file=sys.stderr)
        return 2

    with open(path, "rb") as handle:
        data = handle.read()

    # The features string is one contiguous run of printable ASCII.  It is not
    # necessarily surrounded by NUL bytes, so look for it inside every
    # printable run instead of requiring the run to start with it.
    features_re = re.compile(
        rb"(?:product|release|debug) [a-z0-9_]+(?:[ -][a-z0-9_.+-]+)*"
    )
    candidates = []
    for run in re.findall(rb"[\x20-\x7e]{16,}", data):
        for match in features_re.finditer(run):
            candidates.append(match.group().decode("ascii"))

    if not candidates:
        print(
            "ERROR: no Dart VM features string found in "
            f"{path}. The snapshot was not produced by gen_snapshot.",
            file=sys.stderr,
        )
        return 1

    features = max(candidates, key=len)
    print(f"  libapp.so features string: {features}")

    if not features.startswith("product "):
        print(
            "ERROR: libapp.so was not compiled in product mode "
            f"(features start with '{features.split(' ', 1)[0]}').",
            file=sys.stderr,
        )
        print(
            "       The snapshot and libflutter_engine.so must come from the same "
            "release engine build.",
            file=sys.stderr,
        )
        return 1

    if "no-dedup_instructions" in features:
        print(
            "ERROR: libapp.so carries 'no-dedup_instructions' — it was built by a "
            "non-product gen_snapshot and the engine will abort on startup.",
            file=sys.stderr,
        )
        return 1

    if not any(token in features for token in expected_tokens):
        print(
            f"ERROR: libapp.so features string does not mention the {arch} "
            f"target architecture: {features}",
            file=sys.stderr,
        )
        return 1

    if "linux" not in features:
        print(
            f"ERROR: libapp.so features string does not target Linux: {features}",
            file=sys.stderr,
        )
        return 1

    print("  [OK] libapp.so is a product-mode AOT snapshot for Linux")
    return 0


if __name__ == "__main__":
    sys.exit(main())
