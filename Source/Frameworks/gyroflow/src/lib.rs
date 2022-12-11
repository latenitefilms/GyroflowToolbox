//
//  lib.rs
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

//
// This code is heavily influenced by: https://github.com/gyroflow/gyroflow-ofx/blob/main/src/fisheyestab_v1.rs
//
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

use gyroflow_core::{StabilizationManager, stabilization::RGBAf};

extern crate libc;

#[no_mangle]
pub extern "C" fn processFrame(
    _width: u32,
    _height: u32,
    _path: &str,
    _timestamp: &mut i64,
    _fov: &mut i64,
    _smoothness: &mut i64,
    _lens_correction: &mut i64,
    _buffer: &mut [u8],
    _buffer_size: u32,
) -> i32 {
    println!("[Gyroflow] FROM RUST: processFrame has been triggered!");
    
    let manager = StabilizationManager::<RGBAf>::default();
    
    // TODO: For some reason passing `_path` just crashes, so currently just using a temporary hard coded path:
    
    let tempPath = String::from("/Users/chrishocking/Desktop/A001_06121551_C014.gyroflow");
    let tempPathSlice = tempPath.as_str();
        
    match manager.import_gyroflow_file(&tempPathSlice, true, |_|(), Arc::new(AtomicBool::new(false))) {
        Ok(_) => {
            return 123
        },
        Err(e) => {
            return -1
        }
    }
}



