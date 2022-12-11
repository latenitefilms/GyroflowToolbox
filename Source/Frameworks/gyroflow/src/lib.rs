//
//  lib.rs
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

//
// This code is heavily influenced by: https://github.com/gyroflow/gyroflow-ofx/blob/main/src/fisheyestab_v1.rs
//

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
    
    1 // Currently we're just returning one to say "success". Eventually we actually need to return useful data.
}



