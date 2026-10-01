# MiniNotes

## Migration Status

This repository currently contains two application paths:

1. Legacy desktop/mobile path based on `Qt/QML + C++`.
2. New cross-platform path based on `Flutter + Rust + FFI`.

The new path lives in:

```text
flutter_app/   -> Flutter UI
native_core/   -> Rust core + SQLite + C ABI
```

On the current machine, the detected environment is:

```text
OS       : Windows
Flutter  : 3.41.7
Dart     : 3.11.5
Rust     : 1.93.1
Cargo    : 1.93.1
```

MiniNotes is a small offline-first notes application built with **C++17, QML, Qt and SQLite**. It is designed as a native Qt application with a layered architecture, local persistence, touch-friendly UI, and reproducible builds for Ubuntu Touch and Linux.

> **Development version: 1.0.1**
> **Status: Experimental / Development**

## Status

| Area                       | Current state                                |
| -------------------------- | -------------------------------------------- |
| Application version        | **1.0.1**                                    |
| Ubuntu Touch framework     | `ubuntu-touch-24.04-1.x`                     |
| Ubuntu Touch Click targets | `arm64`, `armhf`, `amd64`                    |
| Linux desktop              | x86_64                                       |
| Linux packages             | `.tar.gz`, `.deb`, `.snap`                   |
| Flatpak                    | CI build working; Flathub submission pending |
| Flatpak runtime            | KDE Platform `6.11`                          |
| Flatpak App ID             | `io.github.ahmadabdelbary2001.mininote`     |
| Language                   | C++17                                        |
| UI                         | QML / Qt Quick Controls                      |
| Database                   | SQLite                                       |
| Build system               | CMake + CMake Presets                        |
| Ubuntu Touch builder       | Clickable 8.10.0                             |
| License                    | MIT                                          |

## Features

MiniNotes currently provides:

* Create notes.
* Edit existing notes.
* Browse saved notes.
* Delete notes with a swipe-to-delete interaction.
* Confirmation before permanent deletion.
* SQLite persistence across application restarts.
* Application-level input validation.
* Prepared SQL statements with bound parameters.
* Automatic note list refresh after create, update or delete.
* `created_at` and `updated_at` timestamps.
* UTF-8 text including Arabic, English, emoji and special characters.
* Touch-friendly QML components and responsive UI metrics.
* Offline/local operation without a backend service.

## Architecture

The application is organized into separate layers:

```text
                         QML UI
                           │
                           ▼
                Presentation layer
              NoteController / Model
                           │
                           ▼
                 Application layer
                    NoteService
                           │
                           ▼
                    Domain layer
                 Note / Repository API
                           │
                           ▼
                      Data layer
                SqliteNoteRepository
                           │
                           ▼
                         SQLite
```

Platform-specific functionality is isolated behind abstractions:

```text
Application / Domain
        │
        ▼
Platform abstraction
        │
        ▼
Qt platform implementation
        │
        ▼
Operating system facilities
```

The main architectural rule is:

```text
QML
 ↓
Presentation
 ↓
Application
 ↓
Domain abstractions
 ↓
Data / Platform implementations
```

The domain and application layers do not access SQLite directly.

## Project Structure

```text
.
├── src/
│   ├── app/
│   │   └── main.cpp
│   ├── application/
│   │   ├── note_service.cpp
│   │   └── note_service.h
│   ├── domain/
│   │   ├── note.h
│   │   └── inote_repository.h
│   ├── data/
│   │   └── sqlite/
│   │       ├── database.cpp
│   │       ├── database.h
│   │       ├── sqlite_note_repository.cpp
│   │       └── sqlite_note_repository.h
│   ├── presentation/
│   │   ├── note_controller.cpp
│   │   ├── note_controller.h
│   │   ├── note_list_model.cpp
│   │   └── note_list_model.h
│   └── platform/
│       ├── platform_paths.h
│       └── qt/
│           ├── qt_platform_paths.cpp
│           └── qt_platform_paths.h
│
├── qml/
│   ├── Main.qml
│   ├── pages/
│   │   ├── CreateNotePage.qml
│   │   ├── EditNotePage.qml
│   │   └── NotesListPage.qml
│   ├── components/
│   │   ├── PageHeader.qml
│   │   ├── NoteEditorForm.qml
│   │   ├── NoteCard.qml
│   │   ├── EmptyNotesState.qml
│   │   ├── FloatingActionButton.qml
│   │   └── DeleteNoteDialog.qml
│   └── theme/
│       └── UiMetrics.qml
│
├── tests/
├── assets/
├── packaging/
│   ├── appstream/
│   └── flatpak/
├── snap/
├── Screenshots/
├── .github/
│   └── workflows/
├── CMakeLists.txt
├── CMakePresets.json
├── clickable.yaml
├── manifest.json.in
├── mininotes.apparmor
├── mininotes.desktop
├── io.github.ahmadabdelbary2001.mininote.yml
└── LICENSE
```

## Technology Stack

### Application

* C++17
* Qt Core
* Qt GUI
* Qt SQL
* Qt QML
* Qt Quick
* SQLite
* QML / Qt Quick Controls

### Build and packaging

* CMake
* CMake Presets
* Clickable
* Snapcraft
* CPack / Debian packaging
* Flatpak / flatpak-builder
* GitHub Actions

The Linux desktop CI uses **Qt 6**.

The Ubuntu Touch Click package uses the `ubuntu-touch-24.04-1.x` framework and its target dependencies defined in `clickable.yaml`.

The CMake project can resolve Qt 5 or Qt 6 depending on the build environment, while the current Linux desktop, Snap and Flatpak builds use Qt 6.

## Requirements

For Linux desktop development, use a modern Ubuntu/Debian-based development environment with:

```text
CMake >= 3.21
C++17 compiler
Qt 6
SQLite / Qt SQL SQLite plugin
Git
```

On Ubuntu:

```bash
sudo apt update

sudo apt install -y \
    build-essential \
    cmake \
    qt6-base-dev \
    qt6-declarative-dev \
    libqt6sql6-sqlite \
    qml6-module-qtquick \
    qml6-module-qtquick-window \
    qml6-module-qtquick-controls \
    qml6-module-qtquick-templates \
    qml6-module-qtquick-layouts \
    qml6-module-qtqml-workerscript
```

Flatpak CI is provided by GitHub Actions. Local Flatpak metadata validation can be performed with `flatpak-builder-lint`; a full local Flatpak build additionally requires the KDE runtime/SDK used by the manifest.

## Linux Desktop Development

### Debug build

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug
```

### Release build

```bash
cmake --preset linux-release
cmake --build --preset linux-release
```

Run the application:

```bash
./build/linux-release/mininotes
```

## Backend Tests

The project provides three QTest targets:

```text
mininotes_backend_test
mininotes_service_test
mininotes_platform_test
```

Build and run all tests:

```bash
cmake --preset linux-tests
cmake --build --preset linux-tests
ctest --preset linux-tests
```

## QML End-to-End Test

Build the E2E target:

```bash
cmake --preset linux-e2e
cmake --build --preset linux-e2e
```

Run it in headless mode:

```bash
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
MININOTES_E2E_TEST=1 \
./build/linux-e2e/mininotes
```

The E2E flow verifies application startup and note workflows including validation, saving, persistence and UI updates.

## Linux Packaging

The Linux package configuration is available through:

```bash
cmake --preset linux-package
cmake --build --preset linux-package
```

The project can generate a Debian package with:

```bash
cpack \
    --config build/linux-package/CPackConfig.cmake \
    -G DEB
```

Release builds produced by CI include:

```text
mininotes_<version>_amd64.deb
mininotes-<version>-linux-x86_64.tar.gz
mininotes_<version>_amd64.snap
```

## Flatpak

MiniNotes has Flatpak packaging based on the KDE Platform `6.11` runtime.

The Flatpak App ID is:

```text
io.github.ahmadabdelbary2001.mininote
```

The main files are:

```text
io.github.ahmadabdelbary2001.mininote.yml
packaging/flatpak/io.github.ahmadabdelbary2001.mininote.desktop
packaging/flatpak/io.github.ahmadabdelbary2001.mininote.metainfo.xml
.github/workflows/flatpak.yml
```

The Flatpak build uses a dedicated CMake option:

```text
-DMININOTES_PACKAGE=ON
-DMININOTES_FLATPAK=ON
```

This keeps Flatpak desktop metadata and installation paths separate from the existing Snap/DEB Linux metadata.

### Flatpak CI

Flatpak CI runs on:

```text
push to main
pull requests
manual workflow dispatch
```

The workflow:

```text
Checkout
   ↓
Flathub Flatpak CI container
   ↓
flatpak-builder
   ↓
KDE Platform 6.11 application build
   ↓
Flatpak bundle
   ↓
GitHub Actions artifact
```

Workflow file:

```text
.github/workflows/flatpak.yml
```

The CI build is currently successful. The resulting Flatpak is uploaded as a GitHub Actions artifact.

### Flatpak metadata validation

The AppStream metadata can be validated locally with:

```bash
flatpak run --command=flatpak-builder-lint \
  org.flatpak.Builder appstream \
  packaging/flatpak/io.github.ahmadabdelbary2001.mininote.metainfo.xml
```

The Flatpak manifest can be validated with:

```bash
flatpak run --command=flatpak-builder-lint \
  org.flatpak.Builder manifest \
  io.github.ahmadabdelbary2001.mininote.yml
```

### Flathub status

The application is prepared for Flathub submission, but it is **not published on Flathub yet**.

The planned distribution flow is:

```text
GitHub repository
        ↓
Flathub submission
        ↓
Review / validation
        ↓
Flathub application repository
        ↓
Published Flatpak
```

Flathub will become the primary public distribution channel for the Flatpak build once the initial submission is accepted.

## Ubuntu Touch Development

MiniNotes uses:

```text
Framework: ubuntu-touch-24.04-1.x
Builder: CMake
Packaging: Clickable
```

Clickable 8 supports explicit architecture selection with `--arch`, which selects the appropriate build environment and output directory.

### Install Clickable

Clickable 8.10.0 is the version used by the CI pipeline.

For example:

```bash
python3 -m pip install --upgrade "clickable-ut==8.10.0"
```

Clickable can also be installed through its documented Ubuntu/PPA or Snap installation methods.

### Check connected devices

```bash
clickable devices
```

### Build for Ubuntu Touch ARM64

```bash
clickable build --arch arm64
```

### Build for ARMHF

```bash
clickable build --arch armhf
```

### Build for AMD64

```bash
clickable build --arch amd64
```

Clickable places the resulting `.click` package in the architecture-specific build directory and automatically runs the package review after a build.

### Install on a connected device

For an ARM64 Ubuntu Touch device:

```bash
clickable install --arch arm64
```

Launch the application:

```bash
clickable launch mininotes
```

View application logs:

```bash
clickable logs
```

## Ubuntu Touch Release Targets

The CI builds the same application for:

```text
arm64
armhf
amd64
```

The primary mobile/device target is ARM64.

The resulting packages are:

```text
mininotes_<version>_arm64.click
mininotes_<version>_armhf.click
mininotes_<version>_amd64.click
```

The three packages belong to the same application version but target different CPU architectures.

## Snap

MiniNotes also has a Linux Snap package.

The Snap build is defined in:

```text
snap/snapcraft.yaml
```

The current Snap configuration uses:

```text
base: core24
Qt 6
strict confinement
MIT license
```

Build locally with Snapcraft:

```bash
snapcraft
```

The CI publishes the resulting Snap to the stable Snap Store channel for versioned releases.

## Distribution

### Ubuntu Touch

The application is distributed through the OpenStore and through the Click artifacts attached to GitHub Releases.

OpenStore:

```text
https://open-store.io/app/mininotes/
```

### Linux

GitHub Releases provide:

```text
Linux x86_64 .tar.gz
Linux amd64 .deb
Linux amd64 .snap
```

### Flatpak

The Flatpak build is currently available as a GitHub Actions artifact. Flathub publication is pending the initial application submission and review.

### GitHub Releases

```text
https://github.com/ahmadabdelbary2001/mininote/releases
```

## CI/CD

The repository uses three main GitHub Actions workflows:

```text
.github/workflows/ubuntu-touch.yml
.github/workflows/linux-desktop.yml
.github/workflows/flatpak.yml
```

### Ubuntu Touch workflow

```text
Checkout
   ↓
Detect version from CMakeLists.txt
   ↓
Host build
   ↓
Backend tests
   ↓
Architecture boundary checks
   ↓
QML E2E
   ↓
Generate release notes
   ↓
Build ARM64
   ↓
Build ARMHF
   ↓
Build AMD64
   ↓
Validate Click packages
   ↓
Publish to OpenStore
```

The Ubuntu Touch matrix uses the corresponding Clickable CI images for each architecture.

### Linux workflow

```text
Checkout
   ↓
Install Qt 6
   ↓
Release build
   ↓
Backend tests
   ↓
QML E2E
   ↓
Startup smoke test
```

### Flatpak workflow

```text
Checkout
   ↓
KDE Flatpak CI container
   ↓
flatpak-builder
   ↓
Application package
   ↓
GitHub Actions artifact
```

The Flatpak workflow is intentionally separate from the Ubuntu Touch and Linux release workflows. Flathub publication is a separate distribution process.

## Automated Releases

Releases use semantic version tags:

```text
vMAJOR.MINOR.PATCH
```

Example:

```text
v1.0.1
```

The application version is taken from:

```text
CMakeLists.txt
```

The release tag must match the application version.

For example:

```text
CMakeLists.txt → 1.0.1
Git tag        → v1.0.1
```

A mismatch stops the release pipeline.

A versioned release automatically produces:

```text
Ubuntu Touch ARM64 .click
Ubuntu Touch ARMHF .click
Ubuntu Touch AMD64 .click
Linux x86_64 .tar.gz
Linux AMD64 .deb
Linux AMD64 .snap
```

The Flatpak workflow is currently CI-based and independent of the release artifact pipeline. Once Flathub publication is established, Flatpak updates will follow the Flathub maintenance workflow.

All release artifacts produced by the release pipeline are attached to the corresponding GitHub Release.

## Automated Changelog

Release notes are generated automatically from Git commits between the previous version tag and the current version tag.

Conventional commit types are grouped into:

```text
feat      → Features
fix       → Fixes
refactor  → Improvements
perf      → Improvements
ui        → Improvements
ux        → Improvements
```

Other maintenance commits are grouped separately under:

```text
Other Changes
```

The generated release notes are reused for:

```text
OpenStore Changelog
        +
GitHub Release notes
```

The Changelog is generated once per release and shared by all Ubuntu Touch architecture builds.

For OpenStore publishing, Clickable supports passing a changelog message directly to `clickable publish`.

## Release Flow

The normal release flow is:

```text
1. Update CMake version
        ↓
2. Implement and test changes
        ↓
3. Update release metadata
        ↓
4. Commit changes
        ↓
5. Push to main
        ↓
6. Verify CI
        ↓
7. Create matching vX.Y.Z tag
        ↓
8. GitHub Actions validates the version
        ↓
9. Build all release targets
        ↓
10. Generate Changelog
        ↓
11. Publish Ubuntu Touch packages
        ↓
12. Publish Snap
        ↓
13. Create / update GitHub Release
        ↓
14. Maintain Flatpak / Flathub separately
```

For the current Flatpak work, `v1.0.1` is the first planned release version containing the Flatpak packaging and CI integration.

## Data and Persistence

Notes are stored locally in SQLite.

The database schema contains:

```sql
CREATE TABLE IF NOT EXISTS notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

The application uses Qt's platform-aware application data paths rather than hard-coded platform-specific paths.

No remote database or backend service is required.

## Security and Data Handling

MiniNotes is designed as a local/offline application:

* Notes are stored locally.
* SQLite access is isolated behind the repository abstraction.
* SQL writes use prepared statements and bound parameters.
* No server is required for normal note-taking.
* Platform-specific storage paths are isolated behind the platform abstraction.

## Development Guidelines

A change should normally include:

1. A successful build.
2. Passing backend tests.
3. Passing relevant QML E2E checks.
4. Verification of persistence behavior.
5. Verification of affected platform packaging.
6. Updated documentation when behavior or build requirements change.

The main documentation file is:

```text
README.md
```

## Future Targets

The architecture is intentionally designed to allow additional Qt-based targets in the future.

Potential future targets include:

```text
Windows
macOS
Android
iOS
```

These targets are **not currently released** and should not be considered supported platforms yet.

## License

MiniNotes is released under the:

```text
MIT License
```

See:

```text
LICENSE
```

for the complete license text.

## Repository

Source code:

```text
https://github.com/ahmadabdelbary2001/mininote
```

Issues and feature requests:

```text
https://github.com/ahmadabdelbary2001/mininote/issues
```

Development and release artifacts:

```text
https://github.com/ahmadabdelbary2001/mininote/releases
```
