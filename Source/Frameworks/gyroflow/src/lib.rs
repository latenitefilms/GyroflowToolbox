//! Stable C ABI between the FxPlug host and Gyroflow Core.
//!
//! Returned strings belong to Rust and must be released with `freeCString`.
//! The v1.3.5 entry points and calling conventions remain available.

mod animation;
mod cache;
mod controls;
mod geometry;
mod parameters;
mod project;
mod render;

pub use render::RenderOptions;

use gyroflow_core::StabilizationManager;
use std::ffi::{CStr, CString, c_char, c_int, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Mutex, Once};

/// Lens profiles are shared until an explicit cache purge, independently of logging.
static LENS_DATABASE: Mutex<Option<StabilizationManager>> = Mutex::new(None);

#[derive(Debug)]
enum BridgeError {
    InvalidInput(&'static str),
    Core(gyroflow_core::GyroflowCoreError),
    Io(std::io::Error),
    Filesystem(gyroflow_core::filesystem::FilesystemError),
    Utf8(std::str::Utf8Error),
    Json(serde_json::Error),
    Panic,
}

impl std::fmt::Display for BridgeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidInput(message) => formatter.write_str(message),
            Self::Core(error) => error.fmt(formatter),
            Self::Io(error) => error.fmt(formatter),
            Self::Filesystem(error) => error.fmt(formatter),
            Self::Utf8(error) => error.fmt(formatter),
            Self::Json(error) => error.fmt(formatter),
            Self::Panic => formatter.write_str("Gyroflow operation panicked"),
        }
    }
}
impl From<gyroflow_core::GyroflowCoreError> for BridgeError {
    fn from(error: gyroflow_core::GyroflowCoreError) -> Self {
        Self::Core(error)
    }
}
impl From<std::io::Error> for BridgeError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}
impl From<gyroflow_core::filesystem::FilesystemError> for BridgeError {
    fn from(error: gyroflow_core::filesystem::FilesystemError) -> Self {
        Self::Filesystem(error)
    }
}
impl From<std::str::Utf8Error> for BridgeError {
    fn from(error: std::str::Utf8Error) -> Self {
        Self::Utf8(error)
    }
}
impl From<serde_json::Error> for BridgeError {
    fn from(error: serde_json::Error) -> Self {
        Self::Json(error)
    }
}
type BridgeResult<Value> = Result<Value, BridgeError>;

/// Returns a generated C header containing the stable parameter identifiers. Free with `freeCString`.
#[unsafe(export_name = "getParameterConstants")]
pub extern "C" fn parameter_constants() -> *const c_char {
    ffi_string(|| Ok(parameters::constants()))
}

/// Validates a complete inspector payload and writes its versioned render options. Returns 1 on success.
///
/// # Safety
/// Input must be a live C string; output must be null or an aligned writable `RenderOptions` until return.
#[unsafe(export_name = "getOptionsFromParameters")]
pub unsafe extern "C" fn options_from_parameters(
    data: *const c_char,
    options: *mut RenderOptions,
) -> c_int {
    ffi_status(|| {
        if options.is_null() || !options.is_aligned() {
            return Err(BridgeError::InvalidInput("invalid options output"));
        }
        // SAFETY: The caller supplies readable input and a valid output allocation.
        let values = render::InspectorValues::parse(unsafe { input_string(data)? })?;
        // SAFETY: Checked alignment and nullability; allocation validity belongs to the caller.
        unsafe {
            options.write(values.options);
        }
        Ok(())
    })
}

/// Renders a complete Rust-defined inspector payload, returning 1 only when Metal processing succeeds.
///
/// # Safety
/// Strings must be valid until return. Textures must be live, distinct Metal textures matching the
/// declared dimensions and format, on the same device, without concurrent writers. Queue may be null.
#[unsafe(export_name = "processFrameWithParameters")]
pub unsafe extern "C" fn process_frame_with_parameters(
    identifier: *const c_char,
    width: u32,
    height: u32,
    format: *const c_char,
    component_bytes: c_int,
    path: *const c_char,
    data: *const c_char,
    timestamp: i64,
    parameters: *const c_char,
    keyframes: *const c_char,
    input_texture: *mut c_void,
    output_texture: *mut c_void,
    command_queue: *mut c_void,
) -> c_int {
    ffi_status(|| {
        // SAFETY: The host owns all borrowed strings and textures throughout this synchronous call.
        let frame = unsafe {
            let values = render::InspectorValues::parse(input_string(parameters)?)?;
            render::Frame {
                identifier: input_string(identifier)?,
                path: input_string(path)?,
                data: input_string(data)?,
                width,
                height,
                timestamp,
                format: render::PixelFormat::parse(input_string(format)?, component_bytes)?,
                settings: values.settings,
                options: values.options,
                disable_stretch: values.disable_stretch,
                host_keyframes: if keyframes.is_null() {
                    None
                } else {
                    Some(input_string(keyframes)?)
                },
                input_texture,
                output_texture,
                command_queue,
            }
        };
        frame.validate()?;
        render::process(frame)
    })
}

fn boundary<Value>(operation: impl FnOnce() -> BridgeResult<Value>) -> BridgeResult<Value> {
    // Only the C boundary catches panics. Poisoned renderer locks are never recovered.
    catch_unwind(AssertUnwindSafe(operation)).unwrap_or(Err(BridgeError::Panic))
}
fn ffi_string(operation: impl FnOnce() -> BridgeResult<String>) -> *const c_char {
    let value = match boundary(operation) {
        Ok(value) => value,
        Err(error) => {
            log::error!("Gyroflow Toolbox: {error}");
            "FAIL".to_owned()
        }
    };
    CString::new(value)
        .unwrap_or_else(|_| c"FAIL".to_owned())
        .into_raw()
}
fn ffi_status(operation: impl FnOnce() -> BridgeResult<()>) -> c_int {
    match boundary(operation) {
        Ok(()) => 1,
        Err(error) => {
            log::error!("Gyroflow Toolbox: {error}");
            0
        }
    }
}

/// # Safety
/// Non-null pointers must reference a NUL-terminated allocation valid for the returned lifetime.
unsafe fn input_string<'input>(pointer: *const c_char) -> BridgeResult<&'input str> {
    if pointer.is_null() {
        return Err(BridgeError::InvalidInput("null string argument"));
    }
    // SAFETY: The FFI caller guarantees the string allocation and its lifetime.
    Ok(unsafe { CStr::from_ptr(pointer) }.to_str()?)
}
fn new_manager() -> StabilizationManager {
    let mut database = LENS_DATABASE.lock().expect("lens database mutex poisoned");
    let shared = database.get_or_insert_with(|| {
        let manager = StabilizationManager::default();
        manager.lens_profile_db.write().load_all();
        manager
    });
    StabilizationManager {
        lens_profile_db: std::sync::Arc::clone(&shared.lens_profile_db),
        ..StabilizationManager::default()
    }
}

fn release_lens_database() {
    let retired = LENS_DATABASE
        .lock()
        .expect("lens database mutex poisoned")
        .take();
    drop(retired);
}

/// Returns inspector values for the additional Core controls as an owned JSON object, or "FAIL".
///
/// # Safety
/// `data` must be null or a valid NUL-terminated project string until return.
#[unsafe(export_name = "getEngineControlDefaults")]
pub unsafe extern "C" fn engine_control_defaults(data: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        let source = unsafe { input_string(data)? };
        let values = project::inspect(source, |manager| {
            let mut values = controls::defaults(manager);
            if let Some(rotation) = project::input_rotation(source, manager) {
                values["170"] = rotation.into();
            }
            values
        })?;
        Ok(serde_json::to_string(&values)?)
    })
}

/// Exports inspector settings and animation as a portable Gyroflow project, or owned "FAIL".
///
/// # Safety
/// Strings must be valid until return. Options must be null or an aligned readable `RenderOptions`.
#[unsafe(export_name = "exportConfiguredProject")]
pub unsafe extern "C" fn export_configured_project(
    data: *const c_char,
    snapshot: *const c_char,
    options: *const RenderOptions,
) -> *const c_char {
    ffi_string(|| {
        if options.is_null() || !options.is_aligned() {
            return Err(BridgeError::InvalidInput("invalid export options"));
        }
        // SAFETY: The caller supplies live C strings and a readable options allocation.
        unsafe {
            render::export_project(input_string(data)?, input_string(snapshot)?, options.read())
        }
    })
}

/// Starts optional file logging once per renderer process.
///
/// # Safety
/// `log_path` must be null or a valid NUL-terminated UTF-8 path during this call.
#[unsafe(export_name = "startLogger")]
pub unsafe extern "C" fn start_logger(log_path: *const c_char) {
    static LOGGER: Once = Once::new();
    let _ = ffi_status(|| {
        // SAFETY: Guaranteed by this entry point's caller.
        let path = unsafe { input_string(log_path)? };
        LOGGER.call_once(|| {
            log_panics::init();
            let mut config = simplelog::ConfigBuilder::new();
            for target in ["mp4parse", "wgpu", "naga", "akaze", "ureq", "rustls"] {
                config.add_filter_ignore_str(target);
            }
            if let Ok(file) = std::fs::File::create(path) {
                let _ = simplelog::WriteLogger::init(log::LevelFilter::Info, config.build(), file);
            }
        });
        Ok(())
    });
}

/// Reads legacy inspector defaults, preserving their v1.3.5 units.
///
/// Returns an owned "OK" or "FAIL"; outputs remain untouched on failure.
///
/// # Safety
/// Input must be null or a valid C string. Outputs must be null or distinct, aligned,
/// writable doubles, with all allocations valid until return.
#[unsafe(export_name = "getDefaultValues")]
pub unsafe extern "C" fn default_values(
    data: *const c_char,
    fov: *mut f64,
    smoothness: *mut f64,
    lens_correction: *mut f64,
    horizon_lock: *mut f64,
    horizon_roll: *mut f64,
    position_x: *mut f64,
    position_y: *mut f64,
    video_rotation: *mut f64,
) -> *const c_char {
    ffi_string(|| {
        let outputs = [
            fov,
            smoothness,
            lens_correction,
            horizon_lock,
            horizon_roll,
            position_x,
            position_y,
            video_rotation,
        ];
        if outputs
            .iter()
            .any(|pointer| pointer.is_null() || !pointer.is_aligned())
        {
            return Err(BridgeError::InvalidInput(
                "invalid default-value output pointer",
            ));
        }
        // SAFETY: The caller owns the input for this call.
        let values = project::inspect(unsafe { input_string(data)? }, |manager| {
            let parameters = manager.params.read();
            let smoothing = manager.smoothing.read();
            [
                parameters.fov,
                smoothing.current().get_parameter("smoothness"),
                parameters.lens_correction_amount * 100.0,
                smoothing.horizon_lock.horizonlockpercent,
                smoothing.horizon_lock.horizonroll,
                parameters.adaptive_zoom_center_offset.0,
                parameters.adaptive_zoom_center_offset.1,
                parameters.video_rotation,
            ]
        })?;
        for (pointer, value) in outputs.into_iter().zip(values) {
            // SAFETY: Outputs were checked above; allocation validity is the caller's contract.
            unsafe { pointer.write(value) };
        }
        Ok("OK".into())
    })
}

/// Writes legacy-compatible render defaults, returning 1 on success.
///
/// # Safety
/// Output must be null or point to an aligned writable `RenderOptions` until return.
#[unsafe(export_name = "getRenderDefaults")]
pub unsafe extern "C" fn render_defaults(options: *mut RenderOptions) -> c_int {
    ffi_status(|| {
        if options.is_null() || !options.is_aligned() {
            return Err(BridgeError::InvalidInput(
                "invalid render-options output pointer",
            ));
        }
        // SAFETY: Validated output pointer; allocation validity is the caller's contract.
        unsafe { options.write(RenderOptions::default()) };
        Ok(())
    })
}

/// Reads advanced defaults from an imported project, returning 1 on success.
///
/// # Safety
/// Input must be a valid C string. Output must point to an aligned writable
/// `RenderOptions`. Both allocations must remain valid for this call.
#[unsafe(export_name = "getAdvancedDefaults")]
pub unsafe extern "C" fn advanced_defaults(
    data: *const c_char,
    options: *mut RenderOptions,
) -> c_int {
    ffi_status(|| {
        if options.is_null() || !options.is_aligned() {
            return Err(BridgeError::InvalidInput(
                "invalid render-options output pointer",
            ));
        }
        // SAFETY: The caller owns the input for this call.
        let defaults =
            project::inspect(unsafe { input_string(data)? }, RenderOptions::from_project)?;
        // SAFETY: Validated output pointer; allocation validity is the caller's contract.
        unsafe { options.write(defaults) };
        Ok(())
    })
}

/// Returns the lens identifier as an owned C string, or "FAIL".
///
/// # Safety
/// `data` must be null or a valid NUL-terminated UTF-8 string during this call.
#[unsafe(export_name = "getLensIdentifier")]
pub unsafe extern "C" fn lens_identifier(data: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        project::inspect(unsafe { input_string(data)? }, |manager| {
            manager.lens.read().identifier.clone()
        })
    })
}

/// Returns "YES", "NO", or "FAIL" as an owned C string.
///
/// # Safety
/// `data` must be null or a valid NUL-terminated UTF-8 string during this call.
#[unsafe(export_name = "isLensProfileLoaded")]
pub unsafe extern "C" fn lens_profile_loaded(data: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        let loaded = project::inspect(unsafe { input_string(data)? }, |manager| {
            manager.lens.read().calib_dimension.w > 0
        })?;
        Ok(if loaded { "YES" } else { "NO" }.into())
    })
}

/// Returns whether embedded motion data exists, without logging its contents.
///
/// # Safety
/// `data` must be null or a valid NUL-terminated UTF-8 string during this call.
#[unsafe(export_name = "doesGyroflowProjectContainStabilisationData")]
pub unsafe extern "C" fn contains_stabilization_data(data: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        let present = project::inspect(unsafe { input_string(data)? }, |manager| {
            let gyro = manager.gyro.read();
            !gyro.file_metadata.read().raw_imu.is_empty() || !gyro.quaternions.is_empty()
        })?;
        Ok(if present { "YES" } else { "NO" }.into())
    })
}

/// Returns whether the telemetry has accurate timestamps, as "YES", "NO", or "FAIL".
///
/// # Safety
/// `data` must be null or a valid NUL-terminated UTF-8 string during this call.
#[unsafe(export_name = "hasAccurateTimestamps")]
pub unsafe extern "C" fn accurate_timestamps(data: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        let accurate = project::inspect(unsafe { input_string(data)? }, |manager| {
            manager
                .gyro
                .read()
                .file_metadata
                .read()
                .has_accurate_timestamps
        })?;
        Ok(if accurate { "YES" } else { "NO" }.into())
    })
}

/// Applies a lens profile and returns embedded project data, or "FAIL".
///
/// # Safety
/// Both pointers must be null or valid C strings. The host must hold sandbox access
/// to the profile file throughout this call.
#[unsafe(export_name = "loadLensProfile")]
pub unsafe extern "C" fn load_lens_profile(
    data: *const c_char,
    path: *const c_char,
) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees both string allocations.
        let (data, path) = unsafe { (input_string(data)?, input_string(path)?) };
        let manager = project::import(data)?;
        manager.load_lens_profile(path)?;
        project::export_preserving_metadata(&manager, data)
    })
}

/// Applies a preset file while keeping the current clip's telemetry.
///
/// Also accepts the legacy JSON-string input. Returns an owned project or "FAIL".
///
/// # Safety
/// Both pointers must be null or valid C strings. The host must hold sandbox access
/// when passing a preset path.
#[unsafe(export_name = "loadPreset")]
pub unsafe extern "C" fn load_preset(data: *const c_char, path: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees both string allocations.
        let (data, path) = unsafe { (input_string(data)?, input_string(path)?) };
        let manager = project::import(data)?;
        project::import_into(&manager, &project::read_preset(path)?)?;
        project::export_preserving_metadata(&manager, data)
    })
}

/// Imports authorized media and returns embedded project data, or "FAIL".
///
/// # Safety
/// `path` must be null or a valid C string. The host must hold sandbox access to the media.
#[unsafe(export_name = "importMediaFile")]
pub unsafe extern "C" fn import_media_file(path: *const c_char) -> *const c_char {
    ffi_string(|| {
        // SAFETY: The caller guarantees the input allocation.
        let url = gyroflow_core::filesystem::path_to_url(unsafe { input_string(path)? });
        let manager = new_manager();
        let mut file = gyroflow_core::filesystem::open_file(&url, false, false)?;
        let size = file.size;
        let metadata = manager.load_video_file(file.get_file(), size, &url, None, true)?;
        let rotation = project::rotation_from_metadata(metadata.rotation);
        manager.params.write().video_rotation = rotation;
        let mut document: serde_json::Value = serde_json::from_str(&project::export(&manager)?)?;
        document["toolbox_input_rotation"] = rotation.into();
        Ok(serde_json::to_string(&document)?)
    })
}

/// Releases idle cached projects; in-flight frames retain ownership. Returns zero as in v1.3.5.
#[unsafe(export_name = "trashCache")]
pub extern "C" fn trash_cache() -> u32 {
    let _ = ffi_status(|| {
        render::clear_cache();
        project::clear_cache();
        animation::clear_cache();
        // Active frames retain their Arc. Idle lens profiles are released outside the lock,
        // and a later import lazily recreates them without requiring logger initialization.
        release_lens_database();
        Ok(())
    });
    0
}

/// Renders using the legacy v1.3.5 calling convention. Returns 1 only on successful stabilization.
///
/// # Safety
/// Strings must be valid C strings. Textures must be live Metal textures with the specified
/// format and dimensions on the same device, valid until return, without concurrent writers.
/// A non-null queue must belong to that device.
#[unsafe(export_name = "processFrame")]
pub unsafe extern "C" fn process_frame(
    identifier: *const c_char,
    width: u32,
    height: u32,
    format: *const c_char,
    bytes_per_component: c_int,
    path: *const c_char,
    data: *const c_char,
    timestamp: i64,
    fov: f64,
    smoothness: f64,
    lens_correction: f64,
    horizon_lock: f64,
    horizon_roll: f64,
    position_x: f64,
    position_y: f64,
    input_rotation: f64,
    video_rotation: f64,
    overview: u8,
    disable_stretch: u8,
    input_texture: *mut c_void,
    output_texture: *mut c_void,
    command_queue: *mut c_void,
) -> c_int {
    // SAFETY: Both entry points have the same pointer contract.
    unsafe {
        process_frame_v2(
            identifier,
            width,
            height,
            format,
            bytes_per_component,
            path,
            data,
            timestamp,
            fov,
            smoothness,
            lens_correction,
            horizon_lock,
            horizon_roll,
            position_x,
            position_y,
            input_rotation,
            video_rotation,
            overview,
            disable_stretch,
            input_texture,
            output_texture,
            command_queue,
            std::ptr::null(),
        )
    }
}

/// Renders with advanced options and the legacy per-frame parameter behavior.
///
/// # Safety
/// The pointer contracts of [`process_frame_with_keyframes`] apply.
#[unsafe(export_name = "processFrameV2")]
pub unsafe extern "C" fn process_frame_v2(
    identifier: *const c_char,
    width: u32,
    height: u32,
    format: *const c_char,
    bytes_per_component: c_int,
    path: *const c_char,
    data: *const c_char,
    timestamp: i64,
    fov: f64,
    smoothness: f64,
    lens_correction: f64,
    horizon_lock: f64,
    horizon_roll: f64,
    position_x: f64,
    position_y: f64,
    input_rotation: f64,
    video_rotation: f64,
    overview: u8,
    disable_stretch: u8,
    input_texture: *mut c_void,
    output_texture: *mut c_void,
    command_queue: *mut c_void,
    options: *const RenderOptions,
) -> c_int {
    // SAFETY: This entry point forwards the same pointer contract, without a snapshot.
    unsafe {
        process_frame_with_keyframes(
            identifier,
            width,
            height,
            format,
            bytes_per_component,
            path,
            data,
            timestamp,
            fov,
            smoothness,
            lens_correction,
            horizon_lock,
            horizon_roll,
            position_x,
            position_y,
            input_rotation,
            video_rotation,
            overview,
            disable_stretch,
            input_texture,
            output_texture,
            command_queue,
            options,
            std::ptr::null(),
        )
    }
}

/// Renders with advanced options; null options select legacy behavior.
///
/// # Safety
/// All pointer requirements of [`process_frame`] apply. Non-null options must point
/// to an aligned readable `RenderOptions` throughout this call. A non-null snapshot must be a valid C string.
#[unsafe(export_name = "processFrameWithKeyframes")]
pub unsafe extern "C" fn process_frame_with_keyframes(
    identifier: *const c_char,
    width: u32,
    height: u32,
    format: *const c_char,
    bytes_per_component: c_int,
    path: *const c_char,
    data: *const c_char,
    timestamp: i64,
    fov: f64,
    smoothness: f64,
    lens_correction: f64,
    horizon_lock: f64,
    horizon_roll: f64,
    position_x: f64,
    position_y: f64,
    input_rotation: f64,
    video_rotation: f64,
    overview: u8,
    disable_stretch: u8,
    input_texture: *mut c_void,
    output_texture: *mut c_void,
    command_queue: *mut c_void,
    options: *const RenderOptions,
    host_keyframes: *const c_char,
) -> c_int {
    ffi_status(|| {
        // SAFETY: Strings remain owned by the caller until this synchronous operation returns.
        let (identifier, format, path, data) = unsafe {
            (
                input_string(identifier)?,
                input_string(format)?,
                input_string(path)?,
                input_string(data)?,
            )
        };
        let options = if options.is_null() {
            RenderOptions::default()
        } else {
            if !options.is_aligned() {
                return Err(BridgeError::InvalidInput("misaligned render options"));
            }
            // SAFETY: The caller guarantees a readable options struct.
            unsafe { *options }
        };
        let host_keyframes = if host_keyframes.is_null() {
            None
        } else {
            // SAFETY: Snapshot string has the same lifetime contract as the project data.
            Some(unsafe { input_string(host_keyframes)? })
        };
        let request = render::Frame {
            host_keyframes,
            identifier,
            path,
            data,
            width,
            height,
            timestamp,
            format: render::PixelFormat::parse(format, bytes_per_component)?,
            settings: render::Settings {
                fov,
                smoothness,
                lens_correction,
                horizon_lock,
                horizon_roll,
                position_x,
                position_y,
                input_rotation,
                video_rotation,
                overview: overview != 0,
            },
            disable_stretch: disable_stretch != 0,
            input_texture,
            output_texture,
            command_queue,
            options,
        };
        request.validate()?;
        render::process(request)
    })
}

/// Frees a library-owned string; null is accepted.
///
/// # Safety
/// The pointer must be an unmodified, not-yet-freed string returned by this library.
/// Never pass a host-owned allocation.
#[unsafe(export_name = "freeCString")]
pub unsafe extern "C" fn free_c_string(pointer: *mut c_char) {
    if !pointer.is_null() {
        // SAFETY: The caller transfers back the allocation created by CString::into_raw.
        drop(unsafe { CString::from_raw(pointer) });
    }
}

#[cfg(test)]
mod tests;

/// Returns owned JSON descriptors for the additional FxPlug inspector controls.
#[unsafe(export_name = "getPluginParameterDefinitions")]
pub extern "C" fn parameter_definitions() -> *const c_char {
    ffi_string(|| Ok(parameters::definitions().to_string()))
}

/// A synchronous host callback that writes a parameter value at a clip-relative microsecond timestamp.
pub type SampleParameter = unsafe extern "C" fn(*mut c_void, u32, i64, *mut f64) -> c_int;

/// Returns an owned JSON array of host parameter IDs consumed by the Core keyframe provider.
#[unsafe(export_name = "getKeyframeParameterIDs")]
pub extern "C" fn keyframe_parameter_ids() -> *const c_char {
    ffi_string(|| Ok(animation::parameter_ids().to_string()))
}

/// Samples changed host curves into a portable snapshot for rendering in another FxPlug process.
///
/// Neither the callback nor its context is retained. Returns an owned snapshot, or "FAIL".
///
/// # Safety
/// Strings must be valid C strings. The context and callback must remain valid until return.
/// The callback must write the output on success (1), return 0 on failure, and never unwind.
#[unsafe(export_name = "buildHostKeyframes")]
pub unsafe extern "C" fn build_host_keyframes(
    data: *const c_char,
    signature: *const c_char,
    context: *mut c_void,
    sample: Option<SampleParameter>,
) -> *const c_char {
    ffi_string(|| {
        let sample = sample.ok_or(BridgeError::InvalidInput("missing host animation callback"))?;
        // SAFETY: The caller owns the string allocations for the full call.
        let (data, signature) = unsafe { (input_string(data)?, input_string(signature)?) };
        animation::snapshot(data, signature, |parameter, timestamp| {
            let mut value = 0.0;
            // SAFETY: Callback and context remain valid synchronously; output is a live stack double.
            if unsafe { sample(context, parameter, timestamp, &mut value) } != 1 {
                return Err(BridgeError::InvalidInput(
                    "host could not evaluate an animation sample",
                ));
            }
            Ok(value)
        })
    })
}
