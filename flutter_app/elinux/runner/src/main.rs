use std::env;
use std::path::PathBuf;
use flutter_embedder::{
    DartProjectConfig, FlutterDesktopViewMode, FlutterDesktopViewRotation,
    FlutterEngine, FlutterViewController, ViewConfig,
};

/// Under Ubuntu Touch confinement (AppArmor), click apps can only write to:
/// $HOME/.local/share/<package> and $HOME/.cache/<package>
/// Standard path_provider falls back to the executable name if GApplication isn't present.
/// We explicitly set XDG_DATA_HOME and XDG_CACHE_HOME to the confined package path.
fn setup_confined_xdg_dirs() {
    let home = env::var("HOME").unwrap_or_default();
    if home.is_empty() {
        return;
    }

    let package = if let Ok(app_id) = env::var("APP_ID") {
        app_id.split('_').next().unwrap_or("mininotes").to_string()
    } else {
        "mininotes".to_string()
    };

    let data_home = format!("{}/.local/share/{}", home, package);
    let cache_home = format!("{}/.cache/{}", home, package);

    let _ = std::fs::create_dir_all(&data_home);
    let _ = std::fs::create_dir_all(&cache_home);

    unsafe {
        env::set_var("XDG_DATA_HOME", data_home);
        env::set_var("XDG_CACHE_HOME", cache_home);
    }
}

fn resolve_bundle_dir() -> PathBuf {
    // 1. Check if FLUTTER_BUNDLE_DIR or BUNDLE_DIR environment variable is set
    if let Ok(dir) = env::var("FLUTTER_BUNDLE_DIR") {
        let path = PathBuf::from(dir);
        if path.join("data").join("flutter_assets").exists() {
            return path;
        }
    }

    // 2. Resolve relative to current executable location
    if let Ok(exe) = env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            if exe_dir.join("data").join("flutter_assets").exists() {
                return exe_dir.to_path_buf();
            }
        }
    }

    // 3. Fallback to current working directory
    PathBuf::from(".")
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Ubuntu Touch EGL/Wayland platform setting
    if env::var("EGL_PLATFORM").is_err() {
        unsafe {
            env::set_var("EGL_PLATFORM", "wayland");
        }
    }

    setup_confined_xdg_dirs();

    let is_debug = env::var("MININOTE_DEBUG").map(|v| v == "1").unwrap_or(false)
        || env::var("DEBUG").map(|v| v == "1").unwrap_or(false);

    let bundle_dir = resolve_bundle_dir();
    if is_debug {
        eprintln!("[mininote runner] Resolved bundle dir: {:?}", bundle_dir);
    }

    let project_config = DartProjectConfig::from_bundle_dir(&bundle_dir);

    // Initialize Flutter Engine with descriptive logging
    let engine = match FlutterEngine::new(project_config) {
        Ok(e) => e,
        Err(err) => {
            eprintln!("[mininote runner ERROR] Failed to initialize Flutter Engine: {err}");
            eprintln!("  Bundle path: {:?}", bundle_dir);
            eprintln!("  Assets exist: {}", bundle_dir.join("data").join("flutter_assets").exists());
            eprintln!("  ICU data exists: {}", bundle_dir.join("data").join("icudtl.dat").exists());
            return Err(err.into());
        }
    };

    // Configure Wayland view for Ubuntu Touch / Lomiri
    let view_config = ViewConfig {
        width: 720,
        height: 1280,
        view_mode: FlutterDesktopViewMode::Fullscreen,
        view_rotation: FlutterDesktopViewRotation::Rotation0,
        use_mouse_cursor: true,
        use_onscreen_keyboard: true, // Maliit OSK support
        use_window_decoration: false, // Managed by Lomiri
        scale_factor: 1.0,
    };

    // Create View Controller and run event loop
    let controller = match FlutterViewController::new(&view_config, engine) {
        Ok(c) => c,
        Err(err) => {
            eprintln!("[mininote runner ERROR] Failed to create Wayland View Controller: {err}");
            eprintln!("  WAYLAND_DISPLAY: {:?}", env::var("WAYLAND_DISPLAY"));
            eprintln!("  XDG_RUNTIME_DIR: {:?}", env::var("XDG_RUNTIME_DIR"));
            return Err(err.into());
        }
    };

    if is_debug {
        eprintln!("[mininote runner] Entering event loop...");
    }

    controller.run_event_loop();

    if is_debug {
        eprintln!("[mininote runner] Event loop exited cleanly.");
    }

    Ok(())
}
