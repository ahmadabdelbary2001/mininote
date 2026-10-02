import os
import sys
import glob
import json
import urllib.request
import urllib.parse
import uuid

def generate_changelog():
    tag = os.environ.get("GITHUB_REF_NAME", "v1.0.2")
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
            return True
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        print(f"ERROR uploading {filename} [HTTP {e.code}]: {err_msg}", file=sys.stderr)
        return False
    except Exception as ex:
        print(f"ERROR uploading {filename}: {ex}", file=sys.stderr)
        return False

def main():
    api_key = os.environ.get("OPENSTORE_API_KEY", "").strip()
    if not api_key:
        print("OPENSTORE_API_KEY is not configured in environment, skipping OpenStore publication.")
        return

    click_files = glob.glob("dist/click/*.click") + glob.glob("dist/*.click")
    if not click_files:
        print("No .click packages found to upload.")
        return

    changelog = generate_changelog()
    print("Generated Changelog for OpenStore:\n" + changelog)

    success_count = 0
    for click_file in click_files:
        if submit_to_openstore(click_file, api_key, changelog):
            success_count += 1

    print(f"OpenStore publishing complete. Successfully submitted {success_count}/{len(click_files)} packages.")

if __name__ == "__main__":
    main()
