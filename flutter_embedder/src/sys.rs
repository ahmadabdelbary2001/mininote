// FFI definitions for Flutter Embedded Linux (flutter_elinux.h)
// Compatible with NotKit/flutter-embedded-linux @ 4d95294030d703df9b3448d0db5f72adbab7416e

use libc::{c_char, c_int, c_void, wchar_t};

// Opaque handles
pub type FlutterDesktopViewControllerRef = *mut c_void;
pub type FlutterDesktopViewRef = *mut c_void;
pub type FlutterDesktopEngineRef = *mut c_void;
pub type FlutterDesktopPluginRegistrarRef = *mut c_void;
pub type FlutterDesktopMessengerRef = *mut c_void;
pub type FlutterDesktopTextureRegistrarRef = *mut c_void;

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum FlutterDesktopViewMode {
    Normalscreen = 0,
    Fullscreen = 1,
}

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum FlutterDesktopViewRotation {
    Rotation0 = 0,
    Rotation90 = 1,
    Rotation180 = 2,
    Rotation270 = 3,
}

#[repr(C)]
pub struct FlutterDesktopEngineProperties {
    pub assets_path: *const wchar_t,
    pub icu_data_path: *const wchar_t,
    pub aot_library_path: *const wchar_t,
    pub dart_entrypoint_argc: c_int,
    pub dart_entrypoint_argv: *const *const c_char,
}

#[repr(C)]
pub struct FlutterDesktopViewProperties {
    pub width: c_int,
    pub height: c_int,
    pub view_rotation: FlutterDesktopViewRotation,
    pub view_mode: FlutterDesktopViewMode,
    pub use_mouse_cursor: bool,
    pub use_onscreen_keyboard: bool,
    pub use_window_decoration: bool,
    pub force_scale_factor: bool,
    pub scale_factor: f64,
}

#[link(name = "flutter_elinux_wayland")]
unsafe extern "C" {
    pub fn FlutterDesktopEngineCreate(
        engine_properties: *const FlutterDesktopEngineProperties,
    ) -> FlutterDesktopEngineRef;

    pub fn FlutterDesktopEngineDestroy(engine: FlutterDesktopEngineRef) -> bool;

    pub fn FlutterDesktopEngineRun(
        engine: FlutterDesktopEngineRef,
        entry_point: *const c_char,
    ) -> bool;

    pub fn FlutterDesktopEngineProcessMessages(engine: FlutterDesktopEngineRef) -> u64;

    pub fn FlutterDesktopEngineReloadSystemFonts(engine: FlutterDesktopEngineRef);

    pub fn FlutterDesktopEngineGetPluginRegistrar(
        engine: FlutterDesktopEngineRef,
        plugin_name: *const c_char,
    ) -> FlutterDesktopPluginRegistrarRef;

    pub fn FlutterDesktopEngineGetMessenger(
        engine: FlutterDesktopEngineRef,
    ) -> FlutterDesktopMessengerRef;

    pub fn FlutterDesktopEngineGetTextureRegistrar(
        engine: FlutterDesktopEngineRef,
    ) -> FlutterDesktopTextureRegistrarRef;

    pub fn FlutterDesktopViewControllerCreate(
        view_properties: *const FlutterDesktopViewProperties,
        engine: FlutterDesktopEngineRef,
    ) -> FlutterDesktopViewControllerRef;

    pub fn FlutterDesktopViewControllerDestroy(controller: FlutterDesktopViewControllerRef);

    pub fn FlutterDesktopViewControllerGetEngine(
        controller: FlutterDesktopViewControllerRef,
    ) -> FlutterDesktopEngineRef;

    pub fn FlutterDesktopViewControllerGetView(
        controller: FlutterDesktopViewControllerRef,
    ) -> FlutterDesktopViewRef;

    pub fn FlutterDesktopViewDispatchEvent(view: FlutterDesktopViewRef) -> bool;

    pub fn FlutterDesktopViewGetFrameRate(view: FlutterDesktopViewRef) -> i32;
}
