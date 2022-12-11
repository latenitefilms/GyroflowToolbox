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
    println!("[Gyroflow] processFrame has been triggered!");
    321
}
