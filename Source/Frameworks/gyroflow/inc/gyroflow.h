//
//  gyroflow.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 11/12/2022.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//
// This is the "interface" to the Rust code:
//
const char* processFrame(
    uint32_t                    width,
    uint32_t                    height,
    const char*                 pixel_format,
    int                         number_of_bytes,
    const char*                 path,
    const char*                 data,
    int64_t                     timestamp,
    double                      fov,
    double                      smoothness,
    double                      lens_correction,
    unsigned char*              in_buffer,
    uint32_t                    in_buffer_size,
    unsigned char*              out_buffer,
    uint32_t                    out_buffer_size
);
