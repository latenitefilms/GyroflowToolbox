//
//  lib.rs
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Import External Crates:
//---------------------------------------------------------
extern crate libc;                          // Raw FFI bindings to platform libraries like libc
extern crate log;                           // A lightweight logging facade
extern crate oslog;                         // A minimal safe wrapper around Apple's Logging system

//---------------------------------------------------------
// Local name bindings:
//---------------------------------------------------------
use gyroflow_core::{StabilizationManager, stabilization::RGBAf16, stabilization::RGBAf};
use gyroflow_core::gpu::{ BufferDescription, BufferSource };

use lazy_static::*;                         // A macro for declaring lazily evaluated statics
use libc::c_uchar;                          // Allows us to use `*const c_uchar`
use lru::LruCache;                          // A LRU cache implementation
use nalgebra::Vector4;                      // Allows us to use `Vector4`
use std::ffi::CStr;                         // Allows us to use `CStr`
use std::ffi::CString;                      // Allows us to use `CString`
use std::os::raw::c_char;                   // Allows us to use `*const c_uchar`
use std::sync::Arc;                         // Adds Atomic Reference Count support
use std::sync::atomic::AtomicBool;          // The AtomicBool type is a type of atomic variable that can be used in concurrent (multi-threaded) contexts.
use std::sync::Mutex;                       // A mutual exclusion primitive useful for protecting shared data

//---------------------------------------------------------
// We only want to setup the Gyroflow Manager once:
//---------------------------------------------------------

// TODO: Add support for MTLPixelFormatBGRA8Unorm & MTLPixelFormatRGBA32Float

//lazy_static! {
//    static ref EIGHT_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<RGBAf16>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(1).unwrap())); // TODO: Fix if BGRA8Unorm is added.
//}
lazy_static! {
    static ref SIXTEEN_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<RGBAf16>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(1).unwrap()));
}
//lazy_static! {
//    static ref THIRTY_TWO_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<RGBAf>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(1).unwrap()));
//}

//---------------------------------------------------------
// We only want to run the `NSLog` code once:
//---------------------------------------------------------

// TODO: We still get the "Failed to setup logger" error message - so this "run once" code doesn't seem to work:

lazy_static! {
    static ref SETUP_LOGGER: fn() = || {
        if let Err(e) = oslog::OsLogger::new("com.latenitefilms.GyroflowToolbox")
               .level_filter(log::LevelFilter::Debug)
               .category_level_filter("Settings", log::LevelFilter::Trace)
               .init()
        {
            log::error!("[Gyroflow] Failed to setup logger: {:?}", e);
        }
    };
}

//---------------------------------------------------------
// The "Process Frame" function:
//---------------------------------------------------------
#[no_mangle]
pub extern "C" fn processFrame(
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
    in_buffer: *mut c_uchar,
    in_buffer_size: u32,
    out_buffer: *mut c_uchar,
    out_buffer_size: u32
) -> *const c_char {
    //---------------------------------------------------------
    // Setting our NSLog Logger (only once):
    //---------------------------------------------------------
    SETUP_LOGGER();

    // -------------------------------------------------------------------------------
    // You can't use &str across FFI boundary, it's a Rust type.
    // You have to use C-compatible char pointer, so path: *const c_char and then
    // construct CStr from it https://doc.rust-lang.org/std/ffi/struct.CStr.html - CStr::from_ptr(path);
    // and then get &str by calling .to_str().unwrap() or .to_string_lossy()
    // -------------------------------------------------------------------------------
    let path_pointer = unsafe { CStr::from_ptr(path) };
    let path_string = path_pointer.to_string_lossy();

    //---------------------------------------------------------
    // Get Pixel Format:
    //---------------------------------------------------------
    let pixel_format_pointer = unsafe { CStr::from_ptr(pixel_format) };
    let pixel_format_string = pixel_format_pointer.to_string_lossy();

    //---------------------------------------------------------
    // Setup our cache:
    //---------------------------------------------------------
    
    // TODO: Add support for MTLPixelFormatBGRA8Unorm & MTLPixelFormatRGBA32Float
    
    let mut cache;
    //if pixel_format_string == "BGRA8Unorm" {
    //    cache = EIGHT_BIT_CACHE.lock().unwrap();
    //} else if pixel_format_string == "RGBAf16" {
        cache = SIXTEEN_BIT_CACHE.lock().unwrap();
    //} else if pixel_format_string == "RGBAf" {
    //    cache = THIRTY_TWO_BIT_CACHE.lock().unwrap();
    //}
    
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
    let cache_key = format!("{path_string}{width}{height}");
    let manager = if let Some(manager) = cache.get(&cache_key) {
        //---------------------------------------------------------
        // Already cached:
        //---------------------------------------------------------
        manager.clone()
    } else {
        //---------------------------------------------------------
        // Setup the Gyroflow Manager:
        //---------------------------------------------------------
        
        // TODO: Add support for MTLPixelFormatBGRA8Unorm & MTLPixelFormatRGBA32Float
        
        let manager;
        //if pixel_format_string == "BGRA8Unorm" {
        //    manager = StabilizationManager::<RGBAf16>::default();
        //} else if pixel_format_string == "RGBAf16" {
            manager = StabilizationManager::<RGBAf16>::default();
        //} else if pixel_format_string == "RGBAf" {
        //    manager = StabilizationManager::<RGBAf>::default();
        //}

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
                manager.stabilization.write().set_background(background_color);
            },
            Err(e) => {
                //---------------------------------------------------------
                // Return an error message is something fails:
                //---------------------------------------------------------
                log::error!("[Gyroflow Toolbox] Failed to import Gyroflow File: {:?}", e);
            }
        }

        cache.put(cache_key.to_owned(), Arc::new(manager));
        cache.get(&cache_key).unwrap().clone()
    };

    //---------------------------------------------------------
    // Set the FOV:
    //---------------------------------------------------------
    manager.params.write().fov = fov;

    //---------------------------------------------------------
    // Set the Lens Correction:
    //---------------------------------------------------------
    manager.params.write().lens_correction_amount = lens_correction;

    //---------------------------------------------------------
    // Set the Smoothness:
    //---------------------------------------------------------
    manager.smoothing.write().current_mut().set_parameter("smoothness", smoothness);

    //---------------------------------------------------------
    // Invalidate & Recompute, to make sure everything is
    // up-to-date:
    //---------------------------------------------------------
    manager.invalidate_smoothing();
    manager.recompute_blocking();
    manager.params.write().calculate_ramped_timestamps(&manager.keyframes.read());

    //---------------------------------------------------------
    // Calculate buffer size and stride:
    //---------------------------------------------------------
    let input_buffer_size: usize = in_buffer_size as usize;
    let output_buffer_size: usize = out_buffer_size as usize;

    let input_stride: usize = output_width * 4 * number_of_bytes_value;
    let output_stride: usize = output_width * 4 * number_of_bytes_value;

    //---------------------------------------------------------
    // Write debugging information to Console.app:
    //---------------------------------------------------------
    /*
    log::info!("[Gyroflow] width: {:?}", width);
    log::info!("[Gyroflow] height: {:?}", height);
    log::info!("[Gyroflow] path: {:?}", path);
    log::info!("[Gyroflow] path_string: {:?}", path_string);
    log::info!("[Gyroflow] timestamp: {:?}", timestamp);
    log::info!("[Gyroflow] fov: {:?}", fov);
    log::info!("[Gyroflow] smoothness: {:?}", smoothness);
    log::info!("[Gyroflow] lens_correction: {:?}", lens_correction);
    log::info!("[Gyroflow] in_buffer_size: {:?}", in_buffer_size);
    log::info!("[Gyroflow] out_buffer_size: {:?}", out_buffer_size);
    log::info!("[Gyroflow] output_width: {:?}", output_width);
    log::info!("[Gyroflow] output_height: {:?}", output_height);
    log::info!("[Gyroflow] input_stride: {:?}", input_stride);
    log::info!("[Gyroflow] output_stride: {:?}", output_stride);
    */

    //---------------------------------------------------------
    // Stabilization time!
    //---------------------------------------------------------
    let stabilization_result = manager.process_pixels(timestamp, &mut BufferDescription {
        input_size:  (output_width, output_height, input_stride),
        output_size: (output_width, output_height, output_stride),
        input_rect: None,
        output_rect: None,
        buffers: BufferSource::Cpu {
            input:  unsafe { std::slice::from_raw_parts_mut(in_buffer, input_buffer_size) },
            output: unsafe { std::slice::from_raw_parts_mut(out_buffer, output_buffer_size) }
        }
    });

    //---------------------------------------------------------
    // Output the Stabilization result to the Console:
    //---------------------------------------------------------
    //log::info!("[Gyroflow Toolbox] stabilization_result: {:?}", &stabilization_result);

    //---------------------------------------------------------
    // Return "DONE":
    //---------------------------------------------------------
    let result = CString::new("DONE").unwrap();
    return result.into_raw()
}
