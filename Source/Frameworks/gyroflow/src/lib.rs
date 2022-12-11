extern crate libc;
use std::mem;

use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn start_gyroflow(width: u32, height: u32, path: &str) -> i32 {
    println!("[Gyroflow] start_gyroflow has been triggered!");
    321
}

#[no_mangle]
pub extern "C" fn process_pixels(
    timestamp: &mut i64,
    fov: &mut i64,
    smoothness: &mut i64,
    lens_correction: &mut i64,
    buffer: &mut [u8],
    buffer_size: u32,
) -> i32 {
    println!("[Gyroflow] process_pixels has been triggered!");
    321
}

#[no_mangle]
pub extern "C" fn stop_gyroflow() -> i32 {
    println!("[Gyroflow] stop_gyroflow has been triggered!");
    321
}