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
    if let (Ok(app_id), Ok(home)) = (env::var("APP_ID"), env::var("HOME")) {
        let package = app_id.split('_').next().unwrap_or("");
        if !package.is_empty() {
            let data_home = format!("{}/.local/share/{}", home, package);
            let cache_home = format!("{}/.cache/{}", home, package);
            unsafe {
                env::set_var("XDG_DATA_HOME", data_home);
                env::set_var("XDG_CACHE_HOME", cache_home);
            }
        }
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

    let bundle_dir = resolve_bundle_dir();
    let project_config = DartProjectConfig::from_bundle_dir(&bundle_dir);

    // Initialize Flutter Engine
    let engine = FlutterEngine::new(project_config)?;

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
    let controller = FlutterViewController::new(&view_config, engine)?;
    controller.run_event_loop();

    Ok(())
}
