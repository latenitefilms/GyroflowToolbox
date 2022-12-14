//
//  lib.rs
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

// -------------------------------------------------------------------------------
// NOTES:
// -------------------------------------------------------------------------------
//
// This code is heavily influenced by:
// https://github.com/gyroflow/gyroflow-ofx/blob/main/src/fisheyestab_v1.rs
//
// ...and AdrianEddy's comments on the Gyroflow Discord.
//
// i32 = int32_t
// u32 = uint32_t
// i64 = int64_t
// f64 = double
//
// *const c_char = const char *
// *mut c_uchar  = unsigned char *
//
// -------------------------------------------------------------------------------

//---------------------------------------------------------
// Import Libraries:
//---------------------------------------------------------
use libc::c_uchar;                          // Allows us to use `*const c_uchar`
use std::sync::Arc;                         // Adds Atomic Reference Count support
use std::sync::atomic::AtomicBool;          // The AtomicBool type is a type of atomic variable that can be used in concurrent (multi-threaded) contexts.
use std::os::raw::c_char;                   // Allows us to use `*const c_uchar`
use std::ffi::CStr;                         // Allows us to use `CStr`
use std::ffi::CString;                      // Allows us to use `CString`

//---------------------------------------------------------
// Import Gyroflow Core:
//---------------------------------------------------------
use gyroflow_core::{StabilizationManager, stabilization::RGBAf16};
use gyroflow_core::gpu::{ BufferDescription, BufferSource };

//---------------------------------------------------------
// Add C support:
//---------------------------------------------------------
extern crate libc;

//---------------------------------------------------------
// The "Process Frame" function:
//---------------------------------------------------------
#[no_mangle]
pub extern "C" fn processFrame(
    width: u32,
    height: u32,
    path: *const c_char,
    timestamp: i64,
    fov: f64,
    smoothness: f64,
    lens_correction: f64,
    in_buffer: *mut c_uchar, // TODO: I temporarily changed this from *const to try get the Rust code to actually build
    in_buffer_size: u32,
    out_buffer: *mut c_uchar,
    out_buffer_size: u32
) -> *const c_char {
    //---------------------------------------------------------
    // Setup the Gyroflow Manager:
    //---------------------------------------------------------
    let manager = StabilizationManager::<RGBAf16>::default();
    
    // -------------------------------------------------------------------------------
    // You can't use &str across FFI boundary, it's a Rust type.
    // You have to use C-compatible char pointer, so path: *const c_char and then
    // construct CStr from it https://doc.rust-lang.org/std/ffi/struct.CStr.html - CStr::from_ptr(path);
    // and then get &str by calling .to_str().unwrap() or .to_string_lossy()
    // -------------------------------------------------------------------------------
    let path_pointer = unsafe { CStr::from_ptr(path) };
    let path_string = path_pointer.to_string_lossy();
    
    
    //---------------------------------------------------------
    // Import the Gyroflow File:
    //---------------------------------------------------------
    match manager.import_gyroflow_file(&path_string, true, |_|(), Arc::new(AtomicBool::new(false))) {
        Ok(_) => {
            //---------------------------------------------------------
            // Set the Size:
            //---------------------------------------------------------
            // TODO: Work out what values to put in `set_size`:
            //manager.set_size(src_rect.2, src_rect.3);
            
            //---------------------------------------------------------
            // Set the Output Size:
            //---------------------------------------------------------
            // TODO: Is the below code actually correct?
            let output_width: usize = width as usize;
            let output_height: usize = height as usize;
            manager.set_output_size(output_width, output_height);

            //---------------------------------------------------------
            // Set the Interpolation:
            //---------------------------------------------------------
            manager.stabilization.write().interpolation = gyroflow_core::stabilization::Interpolation::Lanczos4;
            
            //---------------------------------------------------------
            // Set the FOV:
            //---------------------------------------------------------
            manager.params.write().fov = fov;
            manager.recompute_undistortion();
        
            //---------------------------------------------------------
            // Set the Lens Correction:
            //---------------------------------------------------------
            manager.params.write().lens_correction_amount = lens_correction;
            manager.recompute_adaptive_zoom();
            manager.recompute_undistortion();
                        
            //---------------------------------------------------------
            // Set the Smoothness:
            //---------------------------------------------------------
            manager.smoothing.write().current_mut().set_parameter("smoothness", smoothness);
            manager.recompute_blocking();
            
            //---------------------------------------------------------
            // Invalidate & Recompute, to make sure everything is
            // up-to-date:
            //---------------------------------------------------------
            manager.invalidate_smoothing();
            manager.recompute_blocking();
            manager.params.write().calculate_ramped_timestamps(&manager.keyframes.read());
                         
            //---------------------------------------------------------
            // Send data in and get data out:
            //---------------------------------------------------------
            let input_buffer_size: usize = in_buffer_size as usize;
            let output_buffer_size: usize = out_buffer_size as usize;
                        
            let input_stride: usize = 0;
            let output_stride: usize = 0;
            
            manager.stabilization.write().process_pixels(timestamp, &mut BufferDescription {
                input_size:  (output_width, output_height, input_stride),   // TODO: The last value is "stride" - what do I use?
                output_size: (output_width, output_height, output_stride),  // TODO: The last value is "stride" - what do I use?
                input_rect: None,                                           // TODO: Do I need this?
                output_rect: None,                                          // TODO: Do I need this?
                buffers: BufferSource::Cpu {
                    input:  unsafe { std::slice::from_raw_parts_mut(in_buffer, input_buffer_size) },
                    output: unsafe { std::slice::from_raw_parts_mut(out_buffer, output_buffer_size) }
                }
            });

            let result = CString::new("DONE").unwrap();
            return result.into_raw()
        },
        Err(_) => { // TODO: Can I get useful error messages from this function?
            let result = CString::new("Failed to import Gyroflow File.").unwrap();
            return result.into_raw()
        }
    }
}



