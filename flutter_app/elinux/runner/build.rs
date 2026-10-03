/// Build script for the mininote eLinux runner.
///
/// This script tells `cargo` (and the linker) where to find the
/// `flutter_elinux_wayland` shared library at **build time**, and instructs
/// the dynamic linker to search the bundle's `lib/` directory at **runtime**
/// via an RPATH entry (`$ORIGIN/lib`).
///
/// Layout expected inside the Click bundle:
///   mininote           ← this binary
///   lib/
///     libflutter_engine.so
///     libflutter_elinux_wayland.so
///     libnative_core.so
///   data/
///     flutter_assets/
///     icudtl.dat
///   lib/libapp.so      ← AOT Dart snapshot (release builds only)
fn main() {
    // ── 1. Linker search path ────────────────────────────────────────────
    // The CI build script copies `libflutter_elinux_wayland.so` and
    // `libflutter_engine.so` into `build/engine-artifacts/<arch>/`.
    // FLUTTER_ENGINE_LIB_DIR is set by build-app.sh to that directory.
    if let Ok(engine_lib_dir) = std::env::var("FLUTTER_ENGINE_LIB_DIR") {
        println!("cargo:rustc-link-search=native={}", engine_lib_dir);
    }

    // Also search the build directory itself (for local / dev builds).
    if let Ok(out_dir) = std::env::var("OUT_DIR") {
        // OUT_DIR is something like target/<triple>/release/build/…/out
        // Walk up to find build/engine-artifacts if it exists.
        let mut p = std::path::PathBuf::from(&out_dir);
        for _ in 0..10 {
            let candidate = p.join("build").join("engine-artifacts");
            if candidate.exists() {
                // We don't know the arch here, so add the parent and let the
                // env-var override take precedence.
                break;
            }
            if !p.pop() {
                break;
            }
        }
        println!("cargo:rustc-link-search=native={}", out_dir);
    }

    // ── 2. Link against the embedder ─────────────────────────────────────
    println!("cargo:rustc-link-lib=dylib=flutter_elinux_wayland");

    // ── 3. RPATH so the runtime linker finds libs next to the binary ─────
    // $ORIGIN resolves to the directory containing the executable at runtime.
    // $ORIGIN/lib is where package-click.sh places all .so files.
    println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN/lib");
    println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");

    // ── 4. Re-run only if this script changes ────────────────────────────
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=FLUTTER_ENGINE_LIB_DIR");
}
