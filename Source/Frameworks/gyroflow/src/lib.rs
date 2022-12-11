extern crate libc;
use std::mem;

use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn start_gyroflow(width: u32, height: u32, path: &str) -> bool {
    println!("[Gyroflow] start_gyroflow has been triggered!");
    true
}

#[no_mangle]
pub extern "C" fn process_pixels(
    timestamp: &mut i64,
    fov: &mut i64,
    smoothness: &mut i64,
    lens_correction: &mut i64,
    buffer: &mut [u8],
    buffer_size: u32,
) -> bool {
    println!("[Gyroflow] process_pixels has been triggered!");
    true
}

#[no_mangle]
pub extern "C" fn stop_gyroflow() -> bool {
    println!("[Gyroflow] stop_gyroflow has been triggered!");
    true
}