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
use gyroflow_core::gpu::{ BufferDescription, BufferSource };

use once_cell::sync::OnceCell;              //
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
// We only want to setup the Gyroflow Manager once for
// each pixel format:
//---------------------------------------------------------
lazy_static! {
    static ref EIGHT_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<BGRA8>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(5).unwrap()));
    static ref SIXTEEN_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<RGBAf16>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(5).unwrap()));
    static ref THIRTY_TWO_BIT_CACHE: Mutex<LruCache<String, Arc<StabilizationManager<RGBAf>>>> = Mutex::new(LruCache::new(std::num::NonZeroUsize::new(5).unwrap()));
}

//---------------------------------------------------------
// The "Process The Frame" function that gets triggered
// in Rust land:
//---------------------------------------------------------
fn process_frame<T: PixelType>(
    cache: &mut LruCache<String, Arc<StabilizationManager<T>>>,
    width: u32,
    height: u32,
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
   let cache_key = format!("{path_string}{output_width}{output_height}");
   let manager = if let Some(manager) = cache.get(&cache_key) {
       //---------------------------------------------------------
       // Already cached:
       //---------------------------------------------------------
       manager.clone()
   } else {
       //---------------------------------------------------------
       // Setup the Gyroflow Manager:
       //---------------------------------------------------------
       let manager = StabilizationManager::<T>::default();
              
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
   // Have parameters changed:
   //---------------------------------------------------------
   let mut params_changed = false;
   {
       let mut params = manager.params.write();
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
    }

   //---------------------------------------------------------
   // Set the Smoothness:
   //---------------------------------------------------------
   {
       let mut smoothing = manager.smoothing.write();
       if smoothing.current().get_parameter("smoothness") != smoothness {
           smoothing.current_mut().set_parameter("smoothness", smoothness);
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
       manager.params.write().calculate_ramped_timestamps(&manager.keyframes.read());
   }
   
   //---------------------------------------------------------
   // Calculate buffer size and stride:
   //---------------------------------------------------------
   let input_buffer_size: usize = in_buffer_size as usize;
   let output_buffer_size: usize = out_buffer_size as usize;

   let input_stride: usize = output_width * 4 * number_of_bytes_value;
   let output_stride: usize = output_width * 4 * number_of_bytes_value;

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
   log::info!("[Gyroflow Toolbox] stabilization_result: {:?}", &stabilization_result);

   //---------------------------------------------------------
   // Return "DONE":
   //---------------------------------------------------------
   let result = CString::new("DONE").unwrap();
   return result.into_raw()
}

//---------------------------------------------------------
// The "Process Frame" function that gets triggered from
// Objective-C Land:
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
    static LOGGER: OnceCell<Mutex<Option<()>>> = OnceCell::new();
    LOGGER.get_or_init(|| {
        let logger = oslog::OsLogger::new("com.latenitefilms.GyroflowToolbox")
            .level_filter(log::LevelFilter::Debug)
            .category_level_filter("Settings", log::LevelFilter::Trace)
            .init().ok();
        Mutex::new(logger)
    });
    
    //---------------------------------------------------------
    // Get Pixel Format:
    //---------------------------------------------------------
    let pixel_format_pointer = unsafe { CStr::from_ptr(pixel_format) };
    let pixel_format_string = pixel_format_pointer.to_string_lossy();
    
    //---------------------------------------------------------
    // Actually process the frame:
    //---------------------------------------------------------
    match pixel_format_string.as_ref() {
        "BGRA8Unorm" => {
            return process_frame::<BGRA8>(&mut EIGHT_BIT_CACHE.lock().unwrap(), width, height, number_of_bytes, path, data, timestamp, fov, smoothness, lens_correction, in_buffer, in_buffer_size, out_buffer, out_buffer_size);
        },
        "RGBAf16" => {
            return process_frame::<RGBAf16>(&mut SIXTEEN_BIT_CACHE.lock().unwrap(), width, height, number_of_bytes, path, data, timestamp, fov, smoothness, lens_correction, in_buffer, in_buffer_size, out_buffer, out_buffer_size);
        },
        "RGBAf" => {
            return process_frame::<RGBAf>(&mut THIRTY_TWO_BIT_CACHE.lock().unwrap(), width, height, number_of_bytes, path, data, timestamp, fov, smoothness, lens_correction, in_buffer, in_buffer_size, out_buffer, out_buffer_size);
        },
        _ => {
            log::error!("[Gyroflow Toolbox] Unsupported pixel format: {:?}", pixel_format_string);
            let result = CString::new("FAIL").unwrap();
            return result.into_raw()
        }
    }
}
