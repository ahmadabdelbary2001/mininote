import os
import sys
import glob
import json
import urllib.request
import urllib.error
import urllib.parse

def get_package_info():
    manifest_path = os.path.join("packaging", "click", "manifest.json")
    if os.path.isfile(manifest_path):
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("name", "mininotes"), data.get("version", "1.0.3")
        except Exception:
            pass
    return "mininotes", "1.0.3"

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

def submit_to_openstore(click_path, api_key, changelog, package_name="mininotes", channel="focal"):
    try:
        import requests
        use_requests = True
    except ImportError:
        use_requests = False

    url = f"https://open-store.io/api/v3/manage/{package_name}/revision"
    filename = os.path.basename(click_path)
    file_size = os.path.getsize(click_path)

    print(f"--> Uploading {filename} ({file_size} bytes) to {url} (channel: {channel})...")

    if use_requests:
        with open(click_path, "rb") as f:
            files = {"file": (filename, f, "application/octet-stream")}
            data = {
                "channel": channel,
                "changelog": changelog,
            }
            params = {"apikey": api_key}
            try:
                resp = requests.post(url, files=files, data=data, params=params, timeout=180)
                if resp.status_code == 200:
                    print(f"SUCCESS: {filename} uploaded successfully. [HTTP 200]")
                    try:
                        print(json.dumps(resp.json(), indent=2))
                    except Exception:
                        print(resp.text)
                    return True, resp.text
                else:
                    err_text = resp.text
                    print(f"ERROR uploading {filename} [HTTP {resp.status_code}]: {err_text}", file=sys.stderr)
                    return False, err_text
            except Exception as ex:
                print(f"ERROR during upload of {filename}: {ex}", file=sys.stderr)
                return False, str(ex)
    else:
        import uuid
        boundary = uuid.uuid4().hex
        with open(click_path, "rb") as f:
            file_bytes = f.read()

        body = bytearray()
        # channel field
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(b'Content-Disposition: form-data; name="channel"\r\n\r\n')
        body.extend(channel.encode("utf-8"))
        body.extend(b"\r\n")

        # changelog field
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(b'Content-Disposition: form-data; name="changelog"\r\n\r\n')
        body.extend(changelog.encode("utf-8"))
        body.extend(b"\r\n")

        # file field
        body.extend(f"--{boundary}\r\n".encode("utf-8"))
        body.extend(f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode("utf-8"))
        body.extend(b"Content-Type: application/octet-stream\r\n\r\n")
        body.extend(file_bytes)
        body.extend(b"\r\n")
        body.extend(f"--{boundary}--\r\n".encode("utf-8"))

        full_url = f"{url}?apikey={urllib.parse.quote(api_key)}"
        req = urllib.request.Request(
            full_url,
            data=bytes(body),
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "User-Agent": "clickable-ut/8.10.0 MiniNotes/1.0.3",
            },
            method="POST"
        )

        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                resp_body = resp.read().decode("utf-8", errors="replace")
                print(f"SUCCESS: {filename} uploaded successfully. [HTTP {resp.status}]:")
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

    package_name, version = get_package_info()
    print(f"=== Publishing {package_name} v{version} to OpenStore ===")

    found_files = glob.glob("dist/click/*.click")
    if not found_files:
        # Fallback to other known locations
        found_files = glob.glob("dist/*.click")
    click_files = list(dict.fromkeys([os.path.abspath(f) for f in found_files if os.path.isfile(f)]))
    if not click_files:
        print("ERROR: No .click packages found to upload to OpenStore.", file=sys.stderr)
        sys.exit(1)

    changelog = generate_changelog()
    print(f"Target OpenStore Package: {package_name}")
    print(f"Found {len(click_files)} Click package(s):")
    for f in click_files:
        print(f"  - {os.path.basename(f)}")

    success_count = 0
    failures = []

    for click_file in sorted(click_files):
        fname = os.path.basename(click_file)
        success, details = submit_to_openstore(
            click_path=click_file,
            api_key=api_key,
            changelog=changelog,
            package_name=package_name,
            channel="focal"
        )
        if success:
            success_count += 1
            print(f"==> SUCCESS: {fname} published to OpenStore.\n")
        else:
            failures.append((fname, details))
            print(f"==> FAILURE: {fname} failed to publish to OpenStore.\n", file=sys.stderr)

    print(f"OpenStore Publication Summary: {success_count}/{len(click_files)} succeeded.")

    if failures:
        print("\nFailed packages:", file=sys.stderr)
        for fname, err in failures:
            print(f"  - {fname}: {err}", file=sys.stderr)
        sys.exit(1)

    print(f"All {success_count} Click package(s) were successfully published to OpenStore!")

if __name__ == "__main__":
    main()

