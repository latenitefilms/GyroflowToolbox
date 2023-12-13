//! # Gyroflow Toolbox: Rust Interface
//!
//! This module allows for communication between the Gyroflow Toolbox Objective-C FxPlug4 code and the `gyroflow_core` Rust library.

//---------------------------------------------------------
// Local name bindings:
//---------------------------------------------------------
use gyroflow_core::{StabilizationManager, stabilization::*};
use gyroflow_core::gpu::{ BufferDescription, BufferSource, Buffers };

use once_cell::sync::OnceCell;              // Provides two new cell-like types, unsync::OnceCell and sync::OnceCell
use lazy_static::*;                         // A macro for declaring lazily evaluated statics
use lru::LruCache;                          // A LRU cache implementation
use nalgebra::Vector4;                      // Allows us to use `Vector4`
use std::ffi::CStr;                         // Allows us to use `CStr`
use std::ffi::CString;                      // Allows us to use `CString`
use std::os::raw::c_char;                   // Allows us to use `*const c_uchar`
use std::sync::Arc;                         // Adds Atomic Reference Count support
use std::sync::atomic::AtomicBool;          // The AtomicBool type is a type of atomic variable that can be used in concurrent (multi-threaded) contexts.
use std::sync::Mutex;                       // A mutual exclusion primitive useful for protecting shared data

//---------------------------------------------------------
// Start writing log files to disk:
//---------------------------------------------------------
#[no_mangle]
pub extern "C" fn startLogger(
    log_path: *const c_char,
) {
    log_panics::init();

    log::error!("[Gyroflow Toolbox Rust] Starting Rust Logger...");
    log::error!("[Gyroflow Toolbox Rust] log path: {:?}", log_path);

    let log_path_pointer = unsafe { CStr::from_ptr(log_path) };
    let log_path_string = log_path_pointer.to_string_lossy();

    let log_config = [ "mp4parse", "wgpu", "naga", "akaze", "ureq", "rustls", "ofx" ]
        .into_iter()
        .fold(simplelog::ConfigBuilder::new(), |mut cfg, x| { cfg.add_filter_ignore_str(x); cfg })
        .build();

    if let Ok(file_log) = std::fs::File::create(log_path_string.as_ref()) {
        let _ = simplelog::WriteLogger::init(log::LevelFilter::Debug, log_config, file_log);
    }
    
    //---------------------------------------------------------
    // Load the Lens Profiles:
    //---------------------------------------------------------
    let stab = StabilizationManager::default();
    stab.lens_profile_db.write().load_all();
    let mut lock = MANAGER_CACHE.lock().unwrap();
    lock.put("lens-profiles".into(), Arc::new(stab));
}

// This code block defines a lazy static variable called `MANAGER_CACHE` that is a `Mutex`-protected LRU cache of `StabilizationManager` instances.
//
// The `lazy_static!` macro is used to ensure that the variable is initialized only once, and only when it is first accessed.
//
// The `Mutex` is used to ensure that the cache can be safely accessed from multiple threads.
//
// The `LruCache` is used to limit the size of the cache to 8 items.
//
// # Example
//
// ```rust
// use gyroflow::MANAGER_CACHE;
//
// let cache = MANAGER_CACHE.lock().unwrap();
// let manager = cache.get("my_pixel_format").unwrap();
// ```
lazy_static! {
    static ref MANAGER_CACHE: Mutex<LruCache<String, Arc<StabilizationManager>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(8).unwrap()));
}

/// This function retrieves default values from a Gyroflow Project.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to the Gyroflow Project data.
/// * `fov` - A pointer to the field of view value.
/// * `smoothness` - A pointer to the smoothness value.
/// * `lens_correction` - A pointer to the lens correction value.
/// * `horizon_lock` - A pointer to the horizon lock value.
/// * `horizon_roll` - A pointer to the horizon roll value.
/// * `position_offset_x` - A pointer to the position offset x value.
/// * `position_offset_y` - A pointer to the position offset y value.
/// * `video_rotation` - A pointer to the video rotation value.
///
/// # Safety
///
/// This function is marked as unsafe because it takes a raw pointer as an argument.
/// The caller must ensure that the pointer is valid and that the data it points to is valid and correctly aligned.
///
/// # Returns
///
/// A pointer to a C-style string containing either "OK" or a failure string.
///
/// # Example
///
/// ```rust
/// use gyroflow::getDefaultValues;
///
/// let gyroflow_project_data = "Gyroflow Project Data".as_ptr() as *const c_char;
/// let fov: *mut f64 = std::ptr::null_mut();
/// let smoothness: *mut f64 = std::ptr::null_mut();
/// let lens_correction: *mut f64 = std::ptr::null_mut();
/// let horizon_lock: *mut f64 = std::ptr::null_mut();
/// let horizon_roll: *mut f64 = std::ptr::null_mut();
/// let position_offset_x: *mut f64 = std::ptr::null_mut();
/// let position_offset_y: *mut f64 = std::ptr::null_mut();
/// let video_rotation: *mut f64 = std::ptr::null_mut();
///
/// let result = unsafe {
///     getDefaultValues(
///         gyroflow_project_data,
///         fov,
///         smoothness,
///         lens_correction,
///         horizon_lock,
///         horizon_roll,
///         position_offset_x,
///         position_offset_y,
///         video_rotation,
///     )
/// };
///
/// assert_eq!(result, "OK");
/// ```
#[no_mangle]
pub extern "C" fn getDefaultValues(
    gyroflow_project_data: *const c_char,
    fov: *mut f64,
    smoothness: *mut f64,
    lens_correction: *mut f64,
    horizon_lock: *mut f64,
    horizon_roll: *mut f64,
    position_offset_x: *mut f64,
    position_offset_y: *mut f64,
    video_rotation: *mut f64,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {

            unsafe {
                let params = stab.params.read();
                let smoothing = stab.smoothing.read();

                *fov = params.fov;
                *smoothness = smoothing.current().get_parameter("smoothness");
                *lens_correction = params.lens_correction_amount * 100.0;
                *horizon_lock = smoothing.horizon_lock.horizonlockpercent;
                *horizon_roll = smoothing.horizon_lock.horizonroll;
                *position_offset_x = params.adaptive_zoom_center_offset.0;
                *position_offset_y = params.adaptive_zoom_center_offset.1;
                *video_rotation = params.video_rotation;
            }

            let result = CString::new("OK").unwrap();
            return result.into_raw()
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Gets the lens identifier.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string containing the Gyroflow Project data.
///
/// # Returns
///
/// A pointer to a C-style string containing the lens identifier or "FAIL".
///
/// # Safety
///
/// This function is marked as unsafe because it accepts a raw pointer as an argument. It is the caller's responsibility to ensure that the pointer is valid and points to a null-terminated string.
#[no_mangle]
pub extern "C" fn getLensIdentifier(
    gyroflow_project_data: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Get the Lens Identifier:
            //---------------------------------------------------------
            let identifier = stab.lens.read().identifier.to_string();
            let result = CString::new(identifier).unwrap();
            return result.into_raw();
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Checks if a lens profile is loaded.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string containing the Gyroflow Project data.
///
/// # Returns
///
/// A pointer to a C-style string containing "YES" if the official lens is loaded, or a failure string otherwise.
///
/// # Safety
///
/// This function is marked as unsafe because it accepts a raw pointer as an argument. It is the caller's responsibility to ensure that the pointer is valid and points to a null-terminated string.
#[no_mangle]
pub extern "C" fn isLensProfileLoaded(
    gyroflow_project_data: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Is official lens loaded?
            //---------------------------------------------------------
            let is_official_lens_loaded = stab.lens.read().calib_dimension.w > 0;
            if is_official_lens_loaded {
                let result = CString::new("YES").unwrap();
                return result.into_raw()
            } else {
                let result = CString::new("NO").unwrap();
                return result.into_raw()
            }
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Determines whether the Gyroflow Project contains Stabilisation Data.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string containing the Gyroflow Project data.
///
/// # Returns
///
/// A pointer to a C-style string containing "YES" if the Gyroflow Project contains Stabilisation Data, or a failure string otherwise.
///
/// # Safety
///
/// This function is marked as unsafe because it accepts a raw pointer as an argument. It is the caller's responsibility to ensure that the pointer is valid and points to a null-terminated string.
#[no_mangle]
pub extern "C" fn doesGyroflowProjectContainStabilisationData(
    gyroflow_project_data: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let mut stab: StabilizationManager = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Check if gyroflow project contains stabilization data:
            //---------------------------------------------------------
            let has_motion = {
                let gyro = stab.gyro.read();

                log::error!("[Gyroflow Toolbox Rust] gyro.file_metadata.raw_imu: {:?}", gyro.file_metadata.raw_imu);
                log::error!("[Gyroflow Toolbox Rust] gyro.file_metadata.quaternions: {:?}", gyro.file_metadata.quaternions);

                log::error!("[Gyroflow Toolbox Rust] gyro.raw_imu: {:?}", gyro.raw_imu);
                log::error!("[Gyroflow Toolbox Rust] gyro.quaternions: {:?}", gyro.quaternions);

                log::error!("[Gyroflow Toolbox Rust] detected_source: {:?}", gyro.file_metadata.detected_source);

                log::error!("[Gyroflow Toolbox Rust] imu_orientation: {:?}", gyro.imu_orientation);
                log::error!("[Gyroflow Toolbox Rust] integration_method: {:?}", gyro.integration_method);
                log::error!("[Gyroflow Toolbox Rust] file_url: {:?}", gyro.file_url);

                !gyro.raw_imu.is_empty() || !gyro.quaternions.is_empty()
            };

            //---------------------------------------------------------
            // Return the result as a string:
            //---------------------------------------------------------
            let result_string = if has_motion {
                "YES"
            } else {
                "NO"
            };

            let result = CString::new(result_string).unwrap();
            return result.into_raw()
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Determines whether the Gyroflow Project data has accurate timestamps.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string containing the Gyroflow Project data.
///
/// # Returns
///
/// * If the project contains accurate timestamps, returns a C-style string containing "YES".
/// * If the project does not contain accurate timestamps, returns a C-style string containing an error message.
#[no_mangle]
pub extern "C" fn hasAccurateTimestamps(
    gyroflow_project_data: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Check if gyroflow project contains stabilization data:
            //---------------------------------------------------------
            let has_accurate_timestamps = {
                let gyro = stab.gyro.read();
                gyro.file_metadata.has_accurate_timestamps
            };

            //---------------------------------------------------------
            // Return the result as a string:
            //---------------------------------------------------------
            let result_string = if has_accurate_timestamps {
                "YES"
            } else {
                "NO"
            };

            let result = CString::new(result_string).unwrap();
            return result.into_raw()
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Load a Lens Profile from a JSON to a supplied Gyroflow Project.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string representing the Gyroflow Project data.
/// * `lens_profile_path` - A pointer to a C-style string representing the Lens Profile data.
///
/// # Returns
///
/// A new Gyroflow Project or "FAIL".
#[no_mangle]
pub extern "C" fn loadLensProfile(
    gyroflow_project_data: *const c_char,
    lens_profile_path: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    //---------------------------------------------------------
    // Convert the Lens Profile data to a `&str`:
    //---------------------------------------------------------
    let lens_profile_path_pointer = unsafe { CStr::from_ptr(lens_profile_path) };
    let lens_profile_path_string = lens_profile_path_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Load Lens Profile:
            //---------------------------------------------------------
            if let Err(e) = stab.load_lens_profile(&lens_profile_path_string) {

                log::error!("[Gyroflow Toolbox Rust] Error loading Lens Profile: {:?}", e);

                let result = CString::new("FAIL").unwrap();
                return result.into_raw()
            }

            //---------------------------------------------------------
            // Export Gyroflow data:
            //---------------------------------------------------------
            let gyroflow_data: String;
            match stab.export_gyroflow_data(gyroflow_core::GyroflowProjectType::WithGyroData, "{}", None) {
                Ok(data) => {
                    gyroflow_data = data;
                    log::info!("[Gyroflow Toolbox Rust] Gyroflow data exported successfully");
                },
                Err(e) => {
                    log::error!("[Gyroflow Toolbox Rust] An error occured: {:?}", e);
                    gyroflow_data = "FAIL".to_string();
                }
            }

            //---------------------------------------------------------
            // Return Gyroflow Project data as string:
            //---------------------------------------------------------
            let result = CString::new(gyroflow_data).unwrap();
            return result.into_raw()
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing Lens Profile: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// Load a Gyroflow Preset to a supplied Gyroflow Project.
///
/// # Arguments
///
/// * `gyroflow_project_data` - A pointer to a C-style string representing the Gyroflow Project data.
/// * `preset_path` - A pointer to a C-style string representing the Profile data.
///
/// # Returns
///
/// A new Gyroflow Project or "FAIL".
#[no_mangle]
pub extern "C" fn loadPreset(
    gyroflow_project_data: *const c_char,
    preset_path: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    //---------------------------------------------------------
    // Convert the Lens Profile data to a `&str`:
    //---------------------------------------------------------
    let preset_path_pointer = unsafe { CStr::from_ptr(preset_path) };
    let preset_path_string = preset_path_pointer.to_string_lossy();

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(),
        blocking,
        None,
        |_|(),
        cancel_flag,
        &mut is_preset
    ) {
        Ok(_) => {
            //---------------------------------------------------------
            // Load Preset:
            //---------------------------------------------------------
            let mut is_preset = false;
            if let Err(e) = stab.import_gyroflow_data(preset_path_string.as_bytes(), true, None, |_|(), Arc::new(AtomicBool::new(false)), &mut is_preset) {
                log::error!("[Gyroflow Toolbox Rust] Error loading Preset: {:?}", e);
                let result = CString::new("FAIL").unwrap();
                return result.into_raw()
            }

            //---------------------------------------------------------
            // Export Gyroflow data:
            //---------------------------------------------------------
            let gyroflow_data: String;
            match stab.export_gyroflow_data(gyroflow_core::GyroflowProjectType::WithGyroData, "{}", None) {
                Ok(data) => {
                    gyroflow_data = data;
                    log::info!("[Gyroflow Toolbox Rust] Gyroflow data exported successfully");
                },
                Err(e) => {
                    log::error!("[Gyroflow Toolbox Rust] An error occured: {:?}", e);
                    gyroflow_data = "FAIL".to_string();
                }
            }

            //---------------------------------------------------------
            // Return Gyroflow Project data as string:
            //---------------------------------------------------------
            let result = CString::new(gyroflow_data).unwrap();
            return result.into_raw()
        },
        Err(e) => {
            //---------------------------------------------------------
            // An error has occurred:
            //---------------------------------------------------------
            log::error!("[Gyroflow Toolbox Rust] Error importing Preset: {:?}", e);

            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
        },
    }
}

/// This function is called from Objective-C land and is responsible for clearing the cache.
///
/// # Returns
///
/// This function returns the size of the cache as a `u32`.
#[no_mangle]
pub extern "C" fn trashCache() -> u32 {
    //---------------------------------------------------------
    // Trash the Cache:
    //---------------------------------------------------------
    let mut cache = MANAGER_CACHE.lock().unwrap();
    cache.clear();

    //---------------------------------------------------------
    // Return the Cache Size:
    //---------------------------------------------------------
    cache.len() as u32
}

/// The "Import Media File" function that gets triggered from Objective-C Land.
///
/// # Arguments
///
/// * `media_file_path` - A pointer to a C-style string containing the path to the media file.
///
/// # Returns
///
/// This function returns the Gyroflow Project as a string or "FAIL".
#[no_mangle]
pub extern "C" fn importMediaFile(
    media_file_path: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the file path to a `&str`:
    //---------------------------------------------------------
    let media_file_path_pointer = unsafe { CStr::from_ptr(media_file_path) };
    let media_file_path_string = media_file_path_pointer.to_string_lossy();

    //log::info!("[Gyroflow Toolbox Rust] media_file_path_string: {:?}", media_file_path_string);

    let mut stab = StabilizationManager::default();
    {
        //---------------------------------------------------------
        // Find first lens profile database with loaded profiles:
        //---------------------------------------------------------
        let lock = MANAGER_CACHE.lock().unwrap();
        for (_, v) in lock.iter() {
            if v.lens_profile_db.read().loaded {
                stab.lens_profile_db = v.lens_profile_db.clone();
                break;
            }
        }
    }

    //---------------------------------------------------------
    // Load video file:
    //---------------------------------------------------------
    match stab.load_video_file(&media_file_path_string, None) {
        Ok(_) => {
            log::info!("[Gyroflow Toolbox Rust] Video file loaded successfully");
        },
        Err(e) => {
            log::error!("[Gyroflow Toolbox Rust] An error occured: {:?}", e);
        }
    }

    //---------------------------------------------------------
    // Export Gyroflow data:
    //---------------------------------------------------------
    let gyroflow_data: String;
    match stab.export_gyroflow_data(gyroflow_core::GyroflowProjectType::WithGyroData, "{}", None) {
        Ok(data) => {
            gyroflow_data = data;
            log::info!("[Gyroflow Toolbox Rust] Gyroflow data exported successfully");
        },
        Err(e) => {
            log::error!("[Gyroflow Toolbox Rust] An error occured: {:?}", e);
            gyroflow_data = "FAIL".to_string();
        }
    }

    //---------------------------------------------------------
    // Return Gyroflow Project data as string:
    //---------------------------------------------------------
    let result = CString::new(gyroflow_data).unwrap();
    return result.into_raw()
}

/// This function is called from Objective-C land to process a video frame.
///
/// # Arguments
///
/// * `unique_identifier` - A pointer to a C-style string containing a unique identifier for the frame.
/// * `width` - The width of the video frame.
/// * `height` - The height of the video frame.
/// * `pixel_format` - A pointer to a C-style string containing the pixel format of the video frame.
/// * `number_of_bytes` - The number of bytes in the video frame.
/// * `path` - A pointer to a C-style string containing the path to the video frame.
/// * `data` - A pointer to a C-style string containing the video frame data.
/// * `timestamp` - The timestamp of the video frame.
/// * `fov` - The field of view of the video frame.
/// * `smoothness` - The smoothness of the video frame.
/// * `lens_correction` - The lens correction of the video frame.
/// * `horizon_lock` - The horizon lock of the video frame.
/// * `horizon_roll` - The horizon roll of the video frame.
/// * `position_offset_x` - The x position offset of the video frame.
/// * `position_offset_y` - The y position offset of the video frame.
/// * `input_rotation` - The input rotation of the video frame.
/// * `video_rotation` - The video rotation of the video frame.
/// * `fov_overview` - The field of view overview of the video frame.
/// * `disable_gyroflow_stretch` - Whether or not to disable Gyroflow stretch.
/// * `in_mtl_tex` - A pointer to the input Metal texture.
/// * `out_mtl_tex` - A pointer to the output Metal texture.
/// * `command_queue` - A pointer to the Metal command queue.
///
/// # Returns
///
/// This function returns "DONE" if successful, otherwise an error message. If successful, the output Metal Texture is stored in `out_mtl_tex`.
#[no_mangle]
pub extern "C" fn processFrame(
    unique_identifier: *const c_char,
    width: u32,
    height: u32,
    pixel_format: *const c_char,
    number_of_bytes: i8,
    path: *const c_char,
    data: *const c_char,
    timestamp: i64,
    fov: f64,
    smoothness: f64,
    lens_correction: f64,
    horizon_lock: f64,
    horizon_roll: f64,
    position_offset_x: f64,
    position_offset_y: f64,
    input_rotation: f64,
    video_rotation: f64,
    fov_overview: u8,
    disable_gyroflow_stretch: u8,
    in_mtl_tex: *mut std::ffi::c_void,
    out_mtl_tex: *mut std::ffi::c_void,
    command_queue: *mut std::ffi::c_void,
) -> *const c_char {
    //---------------------------------------------------------
    // Setting our NSLog Logger (only once):
    //---------------------------------------------------------
    static LOGGER: OnceCell<Mutex<Option<()>>> = OnceCell::new();
    LOGGER.get_or_init(|| {
        let logger = oslog::OsLogger::new("com.latenitefilms.GyroflowToolbox")
            .level_filter(log::LevelFilter::Debug)
            .category_level_filter("Settings", log::LevelFilter::Trace)
            .init().ok();
        Mutex::new(logger)
    });

    //---------------------------------------------------------
    // Have parameters changed:
    //---------------------------------------------------------
    let mut params_changed = false;

    //---------------------------------------------------------
    // Get the Unique Identifier:
    //---------------------------------------------------------
    let unique_identifier_pointer = unsafe { CStr::from_ptr(unique_identifier) };
    let unique_identifier_string = unique_identifier_pointer.to_string_lossy();

    //log::debug!("[Gyroflow Toolbox Rust] unique_identifier_string: {:?}", unique_identifier_string);

    //---------------------------------------------------------
    // Get Pixel Format:
    //---------------------------------------------------------
    let pixel_format_pointer = unsafe { CStr::from_ptr(pixel_format) };
    let pixel_format_string = pixel_format_pointer.to_string_lossy();

    // -------------------------------------------------------------------------------
    // You can't use &str across FFI boundary, it's a Rust type.
    // You have to use C-compatible char pointer, so path: *const c_char and then
    // construct CStr from it https://doc.rust-lang.org/std/ffi/struct.CStr.html - CStr::from_ptr(path);
    // and then get &str by calling .to_str().unwrap() or .to_string_lossy()
    // -------------------------------------------------------------------------------
    let path_pointer = unsafe { CStr::from_ptr(path) };
    let path_string = path_pointer.to_string_lossy();

    //---------------------------------------------------------
    // Convert the output width and height to `usize`:
    //---------------------------------------------------------
    let output_width: usize = width as usize;
    let output_height: usize = height as usize;

    //---------------------------------------------------------
    // Convert the number of bytes to `usize`:
    //---------------------------------------------------------
    let number_of_bytes_value: usize = number_of_bytes as usize;

   //---------------------------------------------------------
   // Cache the manager:
   //---------------------------------------------------------
   let mut cache = MANAGER_CACHE.lock().unwrap();
   let cache_key = format!("{path_string}{output_width}{output_height}{pixel_format_string}{disable_gyroflow_stretch}{unique_identifier_string}");
   let manager = if let Some(manager) = cache.get(&cache_key) {
       //---------------------------------------------------------
       // Already cached:
       //---------------------------------------------------------
       manager.clone()
   } else {
       //---------------------------------------------------------
       // On first load, always Invalidate & Recompute:
       //---------------------------------------------------------
       params_changed = true;

       //---------------------------------------------------------
       // Setup the Gyroflow Manager:
       //---------------------------------------------------------
       let manager = StabilizationManager::default();

       //---------------------------------------------------------
       // Import the Gyroflow Data:
       //---------------------------------------------------------
       let data_slice: &[u8] = unsafe {
           CStr::from_ptr(data).to_bytes()
       };
       let mut is_preset = false;
       match manager.import_gyroflow_data(&data_slice, true, None, |_|(), Arc::new(AtomicBool::new(false)), &mut is_preset) {
           Ok(_) => {
                //---------------------------------------------------------
                // Disable Gyroflow Stretch:
                //---------------------------------------------------------
                if disable_gyroflow_stretch != 0 {
                    manager.disable_lens_stretch();
                }

               //---------------------------------------------------------
               // Set the Input Size:
               //---------------------------------------------------------
               manager.set_size(output_width, output_height);

               //---------------------------------------------------------
               // Set the Output Size:
               //---------------------------------------------------------
               manager.set_output_size(output_width, output_height);

               //---------------------------------------------------------
               // Invert the Frame Buffer:
               //---------------------------------------------------------
               manager.params.write().framebuffer_inverted = true;

               //---------------------------------------------------------
               // Set Stabilisation Settings:
               //---------------------------------------------------------
               {
                    let mut stab = manager.stabilization.write();

                    //---------------------------------------------------------
                    // Set the Interpolation:
                    //---------------------------------------------------------
                    stab.interpolation = gyroflow_core::stabilization::Interpolation::Lanczos4;

                    //---------------------------------------------------------
                    // Share wpgu instances:
                    //---------------------------------------------------------
                    stab.share_wgpu_instances = true;
               }

               //---------------------------------------------------------
               // Force the background color to transparent:
               //---------------------------------------------------------
               let background_color: Vector4<f32> = Vector4::new(0.0, 0.0, 0.0, 0.0);
               manager.set_background_color(background_color);
           },
           Err(e) => {
               //---------------------------------------------------------
               // Return an error message is something fails:
               //---------------------------------------------------------
               log::error!("[Gyroflow Toolbox Rust] Failed to import Gyroflow File: {:?}", e);
           }
       }

       cache.put(cache_key.to_owned(), Arc::new(manager));
       cache.get(&cache_key).unwrap().clone()
   };

   {
       let mut params = manager.params.write();

        //---------------------------------------------------------
        // Set the FOV Overview:
        //---------------------------------------------------------
        let incoming_fov_overview = fov_overview != 0;
        if incoming_fov_overview != params.fov_overview {
            //log::error!("[Gyroflow Toolbox Rust] FOV Changed!");
            params.fov_overview = incoming_fov_overview;
            params_changed = true;
        }

       //---------------------------------------------------------
       // Set the FOV:
       //---------------------------------------------------------
       if params.fov != fov {
           params.fov = fov;
           params_changed = true;
       }

       //---------------------------------------------------------
       // Set the Lens Correction:
       //---------------------------------------------------------
       if params.lens_correction_amount != lens_correction {
           params.lens_correction_amount = lens_correction;
           params_changed = true;
       }

       //---------------------------------------------------------
       // Set the Position Offset X:
       //---------------------------------------------------------
       if params.adaptive_zoom_center_offset.0 != position_offset_x / 100.0 {
            params.adaptive_zoom_center_offset.0 = position_offset_x / 100.0;
            params_changed = true;
       }

       //---------------------------------------------------------
       // Set the Position Offset Y:
       //---------------------------------------------------------
       if params.adaptive_zoom_center_offset.1 != position_offset_y / 100.0 {
            params.adaptive_zoom_center_offset.1 = position_offset_y / 100.0;
            params_changed = true;
        }

       //---------------------------------------------------------
       // Set the Video Rotation:
       //---------------------------------------------------------
       if params.video_rotation != video_rotation {
            params.video_rotation = video_rotation;
            params_changed = true;
       }
    }

   {
       //---------------------------------------------------------
       // Set the Smoothness:
       //---------------------------------------------------------
       let mut smoothing = manager.smoothing.write();
       if smoothing.current().get_parameter("smoothness") != smoothness {
           smoothing.current_mut().set_parameter("smoothness", smoothness);
           params_changed = true;
       }

       //---------------------------------------------------------
       // Set the Horizon Lock:
       //---------------------------------------------------------
       if smoothing.horizon_lock.lock_enabled != (horizon_lock > 0.0) || smoothing.horizon_lock.horizonlockpercent != horizon_lock || smoothing.horizon_lock.horizonroll != horizon_roll {
          smoothing.horizon_lock.set_horizon(horizon_lock, horizon_roll);
          params_changed = true;
       }
   }

   //---------------------------------------------------------
   // If something has changed, Invalidate & Recompute, to
   // make sure everything is up-to-date:
   //---------------------------------------------------------
   if params_changed {
       manager.invalidate_smoothing();
       manager.recompute_blocking();
       manager.params.write().calculate_ramped_timestamps(&manager.keyframes.read(), false, false);
   }

   //---------------------------------------------------------
   // Calculate buffer size and stride:
   //---------------------------------------------------------
   let input_stride: usize = output_width * 4 * number_of_bytes_value;
   let output_stride: usize = output_width * 4 * number_of_bytes_value;

   //---------------------------------------------------------
   // Prepare the Metal Texture Image Buffers:
   //---------------------------------------------------------
   let mut buffers = Buffers {
       output: BufferDescription {
           size: (output_width, output_height, output_stride),
           rect: None,
           data: BufferSource::Metal { texture: out_mtl_tex as *mut metal::MTLTexture, command_queue: command_queue as *mut metal::MTLCommandQueue },
           rotation: None,
           texture_copy: true,
       },
       input: BufferDescription {
           size: (output_width, output_height, input_stride),
           rect: None,
           data: BufferSource::Metal { texture: in_mtl_tex as *mut metal::MTLTexture, command_queue: command_queue as *mut metal::MTLCommandQueue },
           rotation: Some(input_rotation as f32),
           texture_copy: true,
       }
   };

   //log::debug!("[Gyroflow Toolbox Rust] in_mtl_tex: {:?}", in_mtl_tex);
   //log::debug!("[Gyroflow Toolbox Rust] out_mtl_tex: {:?}", out_mtl_tex);

   //---------------------------------------------------------
   // Get the Stabilization Result:
   //---------------------------------------------------------
   let _stabilization_result = match pixel_format_string.as_ref() {
       "BGRA8Unorm" => {
           manager.process_pixels::<BGRA8>(timestamp, &mut buffers)
        },
       "RGBAf16" => {
           manager.process_pixels::<RGBAf16>(timestamp, &mut buffers)
        },
       "RGBAf" => {
           manager.process_pixels::<RGBAf>(timestamp, &mut buffers)
        },
        e => {
            log::error!("[Gyroflow Toolbox Rust] Unsupported pixel format: {:?}", pixel_format_string);
            log::error!("[Gyroflow Toolbox Rust] Error during stabilization: {:?}", e);
            let error_msg = format!("{}", e);
            let result = CString::new(error_msg).unwrap();
            return result.into_raw()
       }
   };

   //---------------------------------------------------------
   // Output the Stabilization result to the Console:
   //---------------------------------------------------------
   log::debug!("[Gyroflow Toolbox Rust] stabilization_result: {:?}", &_stabilization_result);

   //---------------------------------------------------------
   // Return "DONE":
   //---------------------------------------------------------
   let result = CString::new("DONE").unwrap();
   return result.into_raw()
}
