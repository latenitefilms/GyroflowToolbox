//
//  lib.rs
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 10/12/2022.
//

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
// We only want to setup the Gyroflow Manager once for
// each pixel format:
//---------------------------------------------------------
lazy_static! {
    static ref MANAGER_CACHE: Mutex<LruCache<String, Arc<StabilizationManager>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(8).unwrap()));
}

//---------------------------------------------------------
// Does the Gyroflow Project contain Stabilisation Data?
// Returns "PASS" or "FAIL".
//---------------------------------------------------------
#[no_mangle]
pub extern "C" fn doesGyroflowProjectContainStabilisationData(
    gyroflow_project_data: *const c_char,
) -> *const c_char {
    //---------------------------------------------------------
    // Convert the Gyroflow Project data to a `&str`:
    //---------------------------------------------------------
    let gyroflow_project_data_pointer = unsafe { CStr::from_ptr(gyroflow_project_data) };
    let gyroflow_project_data_string = gyroflow_project_data_pointer.to_string_lossy();

    let stab = StabilizationManager::default();

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
                !gyro.file_metadata.raw_imu.is_empty() || !gyro.file_metadata.quaternions.is_empty()
            };

            //---------------------------------------------------------
            // Return the result as a string:
            //---------------------------------------------------------
            let result_string = if has_motion {
                "PASS"
            } else {
                "FAIL"
            };

            let result = CString::new(result_string).unwrap();
            return result.into_raw()
        },
        Err(e) => {
            // Handle the error case            
            log::error!("[Gyroflow Toolbox Rust] Error importing gyroflow data: {:?}", e);
            
            let result = CString::new("FAIL").unwrap();
            return result.into_raw()
        },
    }
}

//---------------------------------------------------------
// Load a Lens Profile to a supplied Gyroflow Project.
// Returns the new Gyroflow Project or "FAIL".
//---------------------------------------------------------
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

    let stab = StabilizationManager::default();

    //---------------------------------------------------------
    // Import the `gyroflow_project_data_string`:
    //---------------------------------------------------------
    let blocking = true;
    let path = Some(std::path::PathBuf::from(&*gyroflow_project_data_string));
    let cancel_flag = Arc::new(AtomicBool::new(false));
    let mut is_preset = false;
    match stab.import_gyroflow_data(
        gyroflow_project_data_string.as_bytes(), 
        blocking, 
        path, 
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
            match stab.export_gyroflow_data(false, false, "{}") {
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
            // Handle the error case            
            log::error!("[Gyroflow Toolbox Rust] Error importing Lens Profile: {:?}", e);
            
            let result = CString::new("FAIL").unwrap();
            return result.into_raw()
        },
    }
}

//---------------------------------------------------------
// The "Trash Cache" function that gets triggered from
// Objective-C Land:
//---------------------------------------------------------
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

//---------------------------------------------------------
// The "Import Media File" function that gets triggered 
// from Objective-C Land:
//---------------------------------------------------------
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
    match stab.export_gyroflow_data(false, false, "{}") {
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

//---------------------------------------------------------
// The "Process Frame" function that gets triggered from
// Objective-C Land:
//---------------------------------------------------------
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
    // Get the Unique Identifier:
    //---------------------------------------------------------
    let unique_identifier_pointer = unsafe { CStr::from_ptr(unique_identifier) };
    let unique_identifier_string = unique_identifier_pointer.to_string_lossy();

    //log::info!("[Gyroflow Toolbox Rust] unique_identifier_string: {:?}", unique_identifier_string);

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
   let cache_key = format!("{path_string}{output_width}{output_height}{pixel_format_string}{unique_identifier_string}");
   let manager = if let Some(manager) = cache.get(&cache_key) {
       //---------------------------------------------------------
       // Already cached:
       //---------------------------------------------------------
       manager.clone()
   } else {
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
               // Set the Interpolation:
               //---------------------------------------------------------
               manager.stabilization.write().interpolation = gyroflow_core::stabilization::Interpolation::Lanczos4;

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

   //---------------------------------------------------------
   // Have parameters changed:
   //---------------------------------------------------------
   let mut params_changed = false;   
   {
       let mut params = manager.params.write();

        //---------------------------------------------------------
        // Set the FOV Overview:
        //---------------------------------------------------------
        let incoming_fov_overview = fov_overview != 0;
        if incoming_fov_overview != params.fov_overview {
            log::error!("[Gyroflow Toolbox Rust] FOV Changed!");
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
   // Stabilization time!
   //---------------------------------------------------------
   let mut buffers = Buffers {
       output: BufferDescription {
           size: (output_width, output_height, output_stride),
           rect: None,
           data: BufferSource::Metal { texture: out_mtl_tex as *mut metal::MTLTexture, command_queue: command_queue as *mut metal::MTLCommandQueue },
           rotation: None,
           texture_copy: false,
       },
       input: BufferDescription {
           size: (output_width, output_height, input_stride),
           rect: None,
           data: BufferSource::Metal { texture: in_mtl_tex as *mut metal::MTLTexture, command_queue: command_queue as *mut metal::MTLCommandQueue },
           rotation: Some(input_rotation as f32),
           texture_copy: false,
       }
   };

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
        _ => {
           log::error!("[Gyroflow Toolbox Rust] Unsupported pixel format: {:?}", pixel_format_string);
           let result = CString::new("FAIL").unwrap();
           return result.into_raw()
       }
   };

   //---------------------------------------------------------
   // Output the Stabilization result to the Console:
   //---------------------------------------------------------
   //log::info!("[Gyroflow Toolbox Rust] stabilization_result: {:?}", &_stabilization_result);

   //---------------------------------------------------------
   // Return "DONE":
   //---------------------------------------------------------
   let result = CString::new("DONE").unwrap();
   return result.into_raw()
}
