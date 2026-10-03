//! Safe Rust wrapper for Flutter Embedded Linux (Wayland)
//!
//! Provides RAII abstractions for `FlutterDesktopEngine` and `FlutterDesktopViewController`.

pub mod sys;

use std::ffi::CString;
use std::path::{Path, PathBuf};
use thiserror::Error;

pub use sys::{FlutterDesktopViewMode, FlutterDesktopViewRotation};

#[derive(Error, Debug)]
pub enum EmbedderError {
    #[error("Failed to initialize Flutter engine")]
    EngineInitFailed,
    #[error("Failed to create Flutter view controller")]
    ViewControllerFailed,
    #[error("Failed to run Flutter engine")]
    EngineRunFailed,
    #[error("Invalid path or string conversion")]
    InvalidPath,
}

#[cfg(unix)]
fn to_wchar_vec(s: &str) -> Vec<libc::wchar_t> {
    s.chars().map(|c| c as libc::wchar_t).chain(std::iter::once(0)).collect()
}

#[cfg(windows)]
fn to_wchar_vec(s: &str) -> Vec<libc::wchar_t> {
    s.encode_utf16().map(|c| c as libc::wchar_t).chain(std::iter::once(0)).collect()
}

/// Project paths configuration for the Flutter Engine
pub struct DartProjectConfig {
    pub assets_path: PathBuf,
    pub icu_data_path: PathBuf,
    pub aot_library_path: Option<PathBuf>,
    pub dart_args: Vec<String>,
}

impl DartProjectConfig {
    /// Creates configuration based on the standard bundle directory layout:
    /// - bundle/data/flutter_assets
    /// - bundle/data/icudtl.dat
    /// - bundle/lib/libapp.so (for release/profile AOT builds)
    pub fn from_bundle_dir<P: AsRef<Path>>(bundle_dir: P) -> Self {
        let b = bundle_dir.as_ref();
        let assets_path = b.join("data").join("flutter_assets");
        let icu_data_path = b.join("data").join("icudtl.dat");
        let aot_lib = b.join("lib").join("libapp.so");
        let aot_library_path = if aot_lib.exists() {
            Some(aot_lib)
        } else {
            None
        };

        Self {
            assets_path,
            icu_data_path,
            aot_library_path,
            dart_args: Vec::new(),
        }
    }
}

/// View properties for configuring the Wayland window
#[derive(Debug, Clone)]
pub struct ViewConfig {
    pub width: i32,
    pub height: i32,
    pub view_mode: FlutterDesktopViewMode,
    pub view_rotation: FlutterDesktopViewRotation,
    pub use_mouse_cursor: bool,
    pub use_onscreen_keyboard: bool,
    pub use_window_decoration: bool,
    pub scale_factor: f64,
}

impl Default for ViewConfig {
    fn default() -> Self {
        Self {
            width: 720,
            height: 1280,
            view_mode: FlutterDesktopViewMode::Fullscreen,
            view_rotation: FlutterDesktopViewRotation::Rotation0,
            use_mouse_cursor: true,
            use_onscreen_keyboard: true,
            use_window_decoration: false,
            scale_factor: 1.0,
        }
    }
}

/// Safe RAII wrapper around `FlutterDesktopEngine`
pub struct FlutterEngine {
    handle: sys::FlutterDesktopEngineRef,
    // Keep wide buffers alive for the duration of the handle
    _assets_w: Vec<libc::wchar_t>,
    _icu_w: Vec<libc::wchar_t>,
    _aot_w: Option<Vec<libc::wchar_t>>,
    _argv_c: Vec<CString>,
    _argv_ptrs: Vec<*const libc::c_char>,
}

impl FlutterEngine {
    pub fn new(config: DartProjectConfig) -> Result<Self, EmbedderError> {
        let assets_str = config.assets_path.to_str().ok_or(EmbedderError::InvalidPath)?;
        let icu_str = config.icu_data_path.to_str().ok_or(EmbedderError::InvalidPath)?;

        let assets_w = to_wchar_vec(assets_str);
        let icu_w = to_wchar_vec(icu_str);

        let (aot_w, aot_ptr) = if let Some(aot_path) = config.aot_library_path {
            let s = aot_path.to_str().ok_or(EmbedderError::InvalidPath)?;
            let vec = to_wchar_vec(s);
            let ptr = vec.as_ptr();
            (Some(vec), ptr)
        } else {
            (None, std::ptr::null())
        };

        let mut argv_c = Vec::new();
        for arg in &config.dart_args {
            let c = CString::new(arg.as_str()).map_err(|_| EmbedderError::InvalidPath)?;
            argv_c.push(c);
        }
        let argv_ptrs: Vec<*const libc::c_char> = argv_c.iter().map(|c| c.as_ptr()).collect();

        let props = sys::FlutterDesktopEngineProperties {
            assets_path: assets_w.as_ptr(),
            icu_data_path: icu_w.as_ptr(),
            aot_library_path: aot_ptr,
            dart_entrypoint_argc: argv_ptrs.len() as libc::c_int,
            dart_entrypoint_argv: if argv_ptrs.is_empty() {
                std::ptr::null()
            } else {
                argv_ptrs.as_ptr()
            },
        };

        let handle = unsafe { sys::FlutterDesktopEngineCreate(&props) };
        if handle.is_null() {
            return Err(EmbedderError::EngineInitFailed);
        }

        Ok(Self {
            handle,
            _assets_w: assets_w,
            _icu_w: icu_w,
            _aot_w: aot_w,
            _argv_c: argv_c,
            _argv_ptrs: argv_ptrs,
        })
    }

    pub fn raw_handle(&self) -> sys::FlutterDesktopEngineRef {
        self.handle
    }

    pub fn run(&self, entry_point: Option<&str>) -> Result<(), EmbedderError> {
        let ep_c = match entry_point {
            Some(ep) => Some(CString::new(ep).map_err(|_| EmbedderError::InvalidPath)?),
            None => None,
        };
        let ep_ptr = ep_c.as_ref().map(|c| c.as_ptr()).unwrap_or(std::ptr::null());

        let ok = unsafe { sys::FlutterDesktopEngineRun(self.handle, ep_ptr) };
        if !ok {
            return Err(EmbedderError::EngineRunFailed);
        }
        Ok(())
    }

    pub fn process_messages(&self) -> u64 {
        unsafe { sys::FlutterDesktopEngineProcessMessages(self.handle) }
    }

    pub fn reload_system_fonts(&self) {
        unsafe { sys::FlutterDesktopEngineReloadSystemFonts(self.handle) };
    }
}

impl Drop for FlutterEngine {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe {
                sys::FlutterDesktopEngineDestroy(self.handle);
            }
            self.handle = std::ptr::null_mut();
        }
    }
}

/// Safe RAII wrapper around `FlutterDesktopViewController`
pub struct FlutterViewController {
    controller: sys::FlutterDesktopViewControllerRef,
    view: sys::FlutterDesktopViewRef,
}

impl FlutterViewController {
    /// Creates the view controller.
    /// Note: `FlutterDesktopViewControllerCreate` takes ownership of the engine,
    /// so we consume `FlutterEngine` and prevent its `Drop` from double-freeing.
    pub fn new(view_config: &ViewConfig, engine: FlutterEngine) -> Result<Self, EmbedderError> {
        let mut engine = engine;
        let engine_raw = engine.handle;
        // Relinquish ownership so engine destructor does not run FlutterDesktopEngineDestroy
        engine.handle = std::ptr::null_mut();

        let props = sys::FlutterDesktopViewProperties {
            width: view_config.width,
            height: view_config.height,
            view_rotation: view_config.view_rotation,
            view_mode: view_config.view_mode,
            use_mouse_cursor: view_config.use_mouse_cursor,
            use_onscreen_keyboard: view_config.use_onscreen_keyboard,
            use_window_decoration: view_config.use_window_decoration,
            force_scale_factor: false,
            scale_factor: view_config.scale_factor,
        };

        let controller = unsafe { sys::FlutterDesktopViewControllerCreate(&props, engine_raw) };
        if controller.is_null() {
            return Err(EmbedderError::ViewControllerFailed);
        }

        let view = unsafe { sys::FlutterDesktopViewControllerGetView(controller) };

        Ok(Self { controller, view })
    }

    /// Dispatches events and renders frames in the main event loop
    pub fn dispatch_event(&self) -> bool {
        if self.view.is_null() {
            return false;
        }
        unsafe { sys::FlutterDesktopViewDispatchEvent(self.view) }
    }

    /// Runs the Wayland event loop until the window is closed
    pub fn run_event_loop(&self) {
        while self.dispatch_event() {
            // events processed
        }
    }
}

impl Drop for FlutterViewController {
    fn drop(&mut self) {
        if !self.controller.is_null() {
            unsafe {
                sys::FlutterDesktopViewControllerDestroy(self.controller);
            }
            self.controller = std::ptr::null_mut();
            self.view = std::ptr::null_mut();
        }
    }
}
