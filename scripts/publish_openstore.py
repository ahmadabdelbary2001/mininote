import os
import sys
import glob
import json
import urllib.request
import urllib.error
import uuid

def generate_changelog():
    for p in [".ci/release-notes/release-notes.md", "release-notes.md"]:
        if os.path.isfile(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    c = f.read().strip()
                    if c:
                        return c
            except Exception:
                pass
    tag = os.environ.get("GITHUB_REF_NAME", "v1.0.3")
    return f"""## Changes in {tag}

### Features
- Complete cross-platform Flutter + Rust (FFI) architecture.
- Added support for Windows (EXE, MSI, MSIX, ZIP), macOS (DMG, ZIP), iOS (IPA, ZIP), Android (Multi-ABI APKs & AAB).
- Restored official MiniNote app icons and high-resolution brand identity.

### Improvements
- Full offline-first SQLite synchronization through native Rust core.
- Optimized app size with LTO and strip symbol compression.
- Responsive mobile UI optimized for Ubuntu Touch and touch screen devices.
"""

def submit_to_openstore(click_path, api_key, changelog):
    url = "https://open-store.io/api/v4/submit"
    boundary = uuid.uuid4().hex
    filename = os.path.basename(click_path)

    with open(click_path, "rb") as f:
        file_bytes = f.read()

    body = bytearray()

    # Add changelog field
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(b'Content-Disposition: form-data; name="changelog"\r\n\r\n')
    body.extend(changelog.encode("utf-8"))
    body.extend(b"\r\n")

    # Add file field
    body.extend(f"--{boundary}\r\n".encode("utf-8"))
    body.extend(f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode("utf-8"))
    body.extend(b"Content-Type: application/octet-stream\r\n\r\n")
    body.extend(file_bytes)
    body.extend(b"\r\n")

    body.extend(f"--{boundary}--\r\n".encode("utf-8"))

    req = urllib.request.Request(
        url,
        data=bytes(body),
        headers={
            "X-Api-Key": api_key,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "User-Agent": "MiniNote-CI/1.0",
        },
        method="POST"
    )

    print(f"Uploading {filename} ({len(file_bytes)} bytes) to OpenStore...")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            resp_body = resp.read().decode("utf-8", errors="replace")
            print(f"OpenStore response for {filename} [HTTP {resp.status}]:")
            print(resp_body)
            return True, resp_body
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        print(f"ERROR uploading {filename} [HTTP {e.code}]: {err_msg}", file=sys.stderr)
        return False, err_msg
    except Exception as ex:
        print(f"ERROR uploading {filename}: {ex}", file=sys.stderr)
        return False, str(ex)

def main():
    api_key = os.environ.get("OPENSTORE_API_KEY", "").strip()
    if not api_key:
        print("ERROR: OPENSTORE_API_KEY is not configured in environment.", file=sys.stderr)
        sys.exit(1)

    found_files = glob.glob("dist/click/*.click") + glob.glob("dist/clicks/*.click") + glob.glob("dist/*.click")
    click_files = list(dict.fromkeys([os.path.abspath(f) for f in found_files if os.path.isfile(f)]))
    if not click_files:
        print("ERROR: No .click packages found to upload to OpenStore.", file=sys.stderr)
        sys.exit(1)

    changelog = generate_changelog()
    print("Using Changelog for OpenStore:\n" + changelog)

    success_count = 0
    failures = []

    # Track architectures
    archs_uploaded = []

    for click_file in sorted(click_files):
        fname = os.path.basename(click_file)
        success, details = submit_to_openstore(click_file, api_key, changelog)
        if success:
            success_count += 1
            archs_uploaded.append(fname)
            print(f"SUCCESS: {fname} submitted to OpenStore.")
        else:
            failures.append((fname, details))
            print(f"FAILURE: {fname} failed to submit to OpenStore: {details}", file=sys.stderr)

    print(f"\nOpenStore Submission Summary: {success_count}/{len(click_files)} succeeded.")

    if failures:
        print("\nFailed packages:", file=sys.stderr)
        for fname, err in failures:
            print(f"  - {fname}: {err}", file=sys.stderr)
        sys.exit(1)

    print("All Click packages were successfully submitted to OpenStore.")

if __name__ == "__main__":
    main()
