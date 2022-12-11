//
//  GyroflowWrapper.c
//  Wrapper Application
//
//  Created by Chris Hocking on 11/12/2022.
//

#include "GyroflowWrapper.h"

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <CoreFoundation/CoreFoundation.h>
void NSLog(CFStringRef format, ...);

#define WriteToConsole(fmt, ...) \
{ \
    NSLog(CFSTR(fmt), ##__VA_ARGS__); \
}

bool startGyroflow(unsigned long width, unsigned long height, const char* path) {
    
    // TODO: Currently this doesn't do anything.
    
    WriteToConsole("[Gyroflow] Starting Gyroflow...");
    WriteToConsole("[Gyroflow] width: %lu\n height: %lu\n path: %s", width, height, path);
    return true;
}

bool processPixels(int64_t* timestamp, int64_t* fov, int64_t* smoothness, int64_t* lensCorrection, uint8_t* buffer, unsigned long bufferSize) {
    
    // TODO: Currently this doesn't do anything.
    
    WriteToConsole("[Gyroflow] Processing Pixels...");
    WriteToConsole("[Gyroflow] timestamp: %lld", *timestamp);
    WriteToConsole("[Gyroflow] fov: %lld", *fov);
    WriteToConsole("[Gyroflow] smoothness: %lld", *smoothness);
    WriteToConsole("[Gyroflow] lensCorrection: %lld", *lensCorrection);
    WriteToConsole("[Gyroflow] bufferSize: %lu", bufferSize);
    return true;
}


bool stopGyroflow(void) {
    
    // TODO: Currently this doesn't do anything.
    
    WriteToConsole("[Gyroflow] Stopping Gyroflow!");
    return true;
}

/*
-------------------
NOTES FROM DISCORD:
-------------------

AdrianEddy writes:

the overall idea of gyroflow_core is this:
1. Create an instance of StabilizationManager with correct underlying processing pixel format (in OpenFX it's 32-bit float RGBA, so StabilizationManager<RGBAf> (line 35 and 49)
2. Call import_gyroflow_file
3. Set additional params like set_size, interpolation and whatever else is specific to the processing environment (lines 64-74)
4. Call invalidate_smoothing() and recompute_blocking() just to be sure everything is calculated and up-to-date
5.  Now get the the timestamp and source pixels from your host, in this case it uses RGBA 32-bit float buffer, and call:
let out = stab.process_pixels(timestamp_us, &mut BufferDescription {
 input_size:  (width, height, stride),
 output_size: (output_width, output_height, output_stride),
 input_rect: None, // optional
 output_rect: None, // optional
 buffers: BufferSource::Cpu {
     input:  unsafe { std::slice::from_raw_parts_mut(src_buf.ptr_mut(0), src_buf.bytes()) },
     output: unsafe { std::slice::from_raw_parts_mut(dst_buf.ptr_mut(0), dst_buf.bytes()) }
 }
});
(lines 237-246)
You can also supply OpenCL buffer if the host supports it (CUDA and Metal surfaces are not supported yet, but they will be)

and that's basically it
line numbers from https://github.com/gyroflow/gyroflow-ofx/blob/main/src/fisheyestab_v1.rs

------------------------------------------------------------------------------------------------
CODE FROM THE OPENFX (https://github.com/gyroflow/gyroflow-ofx/blob/main/src/fisheyestab_v1.rs):
------------------------------------------------------------------------------------------------
 
let gyrodata = StabilizationManager::default();
gyrodata.import_gyroflow_file(&gyrodata_filename, true, |_|(), Arc::new(AtomicBool::new(false))).map_err(|e| {
    error!("load_gyro_data error: {}", &e);
    Error::UnknownError
})?;

let video_size = {
    let mut params = gyrodata.params.write();
    params.framebuffer_inverted = true;
    params.video_size
};

let org_ratio = video_size.0 as f64 / video_size.1 as f64;

let src_rect = Self::get_center_rect(width, height, org_ratio);
gyrodata.set_size(src_rect.2, src_rect.3);
gyrodata.set_output_size(width, height);

{
    let mut stab = gyrodata.stabilization.write();
    stab.interpolation = gyroflow_core::stabilization::Interpolation::Lanczos4;
}

gyrodata.invalidate_smoothing();
gyrodata.recompute_blocking();
gyrodata.params.write().calculate_ramped_timestamps(&gyrodata.keyframes.read());

 
let src = source_image.get_descriptor::<RGBAColourF>()?;
let dst = output_image.get_descriptor::<RGBAColourF>()?;

let mut src_buf = src.data();
let mut dst_buf = dst.data();
let src_stride = src_buf.stride_bytes().abs() as usize;
let out_stride = dst_buf.stride_bytes().abs() as usize;

let out = stab.process_pixels(timestamp_us, &mut BufferDescription {
    input_size:  (src_buf.dimensions().0 as usize, src_buf.dimensions().1 as usize, src_stride),
    output_size: (dst_buf.dimensions().0 as usize, dst_buf.dimensions().1 as usize, out_stride),
    input_rect: Some(src_rect),
    output_rect: None,
    buffers: BufferSource::Cpu {
        input:  unsafe { std::slice::from_raw_parts_mut(src_buf.ptr_mut(0), src_buf.bytes()) },
        output: unsafe { std::slice::from_raw_parts_mut(dst_buf.ptr_mut(0), dst_buf.bytes()) }
    }
});
      
 */
