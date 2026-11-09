// Metal platform harness; all stabilization, settings, and cache behavior execute in Rust.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "gyroflow.h"
#include <math.h>

static BOOL runFormat(id<MTLDevice> device, const char *project, MTLPixelFormat format,
                      const char *formatName, int componentBytes, NSUInteger iterations,
                      NSUInteger width, NSUInteger height) {
    const NSUInteger bytesPerPixel = 4 * componentBytes;
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
        width:width height:height mipmapped:NO];
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> input = [device newTextureWithDescriptor:descriptor];
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!input || !output) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * bytesPerPixel];
    for (NSUInteger pixel = 0; pixel < width * height; pixel++) {
        if (componentBytes == 1) {
            uint8_t *values = (uint8_t *)pixels.mutableBytes + pixel * 4;
            values[0] = 64; values[1] = 128; values[2] = 192; values[3] = 255;
        } else if (componentBytes == 2) {
            _Float16 *values = (_Float16 *)pixels.mutableBytes + pixel * 4;
            values[0] = 0.25; values[1] = 0.5; values[2] = 0.75; values[3] = 1.0;
        } else {
            float *values = (float *)pixels.mutableBytes + pixel * 4;
            values[0] = 0.25; values[1] = 0.5; values[2] = 0.75; values[3] = 1.0;
        }
    }
    [input replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0
        withBytes:pixels.bytes bytesPerRow:width * bytesPerPixel];
    GyroflowRenderOptions options;
    getRenderDefaults(&options);
    for (uint32_t interpolation = 0; interpolation < 7; interpolation++) {
        options.interpolation = interpolation;
        int ok = processFrameV2(formatName, (uint32_t)width, (uint32_t)height, formatName,
            componentBytes, "identity.gyroflow", project, 0, 1.0, 0.5, 1.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0,
            (__bridge void *)input, (__bridge void *)output, NULL, &options);
        if (!ok) { fprintf(stderr, "Render failed: %s interpolation %u\n", formatName, interpolation); return NO; }
        uint8_t actual[16] = {0};
        [output getBytes:actual bytesPerRow:bytesPerPixel
            fromRegion:MTLRegionMake2D(width / 2, height / 2, 1, 1) mipmapLevel:0];
        for (NSUInteger component = 0; component < 4; component++) {
            float value = componentBytes == 1 ? actual[component] / 255.0f :
                componentBytes == 2 ? ((const _Float16 *)actual)[component] : ((const float *)actual)[component];
            float expected = componentBytes == 1 ? ((const uint8_t *)pixels.bytes)[component] / 255.0f :
                (component == 3 ? 1.0f : (component + 1) * 0.25f);
            if (!isfinite(value) || fabsf(value - expected) > 0.015f) {
                fprintf(stderr, "Pixel mismatch: %s filter %u channel %lu: %f != %f\n",
                    formatName, interpolation, (unsigned long)component, value, expected);
                return NO;
            }
        }
    }
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    for (NSUInteger frame = 0; frame < iterations; frame++) {
        @autoreleasepool {
            if (!processFrame(formatName, (uint32_t)width, (uint32_t)height, formatName, componentBytes,
                "identity.gyroflow", project, (int64_t)((frame % 30) * 33333),
                1.0, 0.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, 0,
                (__bridge void *)input, (__bridge void *)output, NULL)) return NO;
        }
    }
    printf("PASS: %s, seven filters, %lu warm frames, %.3f ms/frame (%lux%lu synthetic fixture)\n",
        formatName, (unsigned long)iterations, (CFAbsoluteTimeGetCurrent() - start) * 1000.0 / iterations,
        (unsigned long)width, (unsigned long)height);
    return YES;
}

static NSString *snapshot(double inputRotation, double videoRotation) {
    const char *identifiersString = getKeyframeParameterIDs();
    NSData *data = [NSData dataWithBytes:identifiersString length:strlen(identifiersString)];
    freeCString((char *)identifiersString);
    NSArray *identifiers = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSNumber *identifier in identifiers) {
        double value = identifier.intValue == 100 ? 1.0 : identifier.intValue == 110 ? 0.5 :
            identifier.intValue == 180 ? videoRotation : identifier.intValue == 210 ? 130.0 : 0.0;
        [rows addObject:@[identifier, @[@[@0, @(value)]]]];
    }
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:@[@2, @(inputRotation), rows, NSNull.null] options:0 error:NULL];
    return [[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding];
}

/// Four asymmetric quadrants detect rotation, double rotation, cropping, and black output.
static BOOL runGeometry(id<MTLDevice> device, const char *project, NSUInteger width, NSUInteger height,
                        double inputRotation, double videoRotation) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:width height:height mipmapped:NO];
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> input = [device newTextureWithDescriptor:descriptor];
    id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
    if (!input || !output) return NO;
    const uint32_t colors[] = { 0xFFFF0000, 0xFF00FF00, 0xFF0000FF, 0xFFFFFF00 };
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    for (NSUInteger row = 0; row < height; row++) {
        for (NSUInteger column = 0; column < width; column++) {
            ((uint32_t *)pixels.mutableBytes)[row * width + column] = colors[(row >= height / 2 ? 2 : 0) + (column >= width / 2 ? 1 : 0)];
        }
    }
    [input replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:width * 4];
    GyroflowRenderOptions options;
    getRenderDefaults(&options);
    options.use_project_keyframes = 0;
    NSString *curves = snapshot(inputRotation, videoRotation);
    // Fit the rotated frame using Core's zoom calculation. With zoom disabled,
    // FOV is measured against the original landscape width, not the portrait width.
    NSData *projectData = [NSData dataWithBytes:project length:strlen(project)];
    NSMutableDictionary *geometryProject = [NSJSONSerialization JSONObjectWithData:projectData options:NSJSONReadingMutableContainers error:NULL];
    geometryProject[@"stabilization"][@"adaptive_zoom_window"] = @-1.0;
    geometryProject[@"stabilization"][@"max_zoom"] = NSNull.null;
    NSString *fittedProject = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:geometryProject options:0 error:NULL] encoding:NSUTF8StringEncoding];
    if (!processFrameWithKeyframes("geometry", (uint32_t)width, (uint32_t)height, "BGRA8", 1,
        "geometry.gyroflow", fittedProject.UTF8String, 0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0,
        inputRotation, videoRotation, 0, 0, (__bridge void *)input, (__bridge void *)output, NULL, &options, curves.UTF8String)) return NO;
    for (NSUInteger quadrant = 0; quadrant < 4; quadrant++) {
        uint32_t actual = 0;
        NSUInteger column = (quadrant % 2 ? 3 : 1) * width / 4;
        NSUInteger row = (quadrant / 2 ? 3 : 1) * height / 4;
        [output getBytes:&actual bytesPerRow:4 fromRegion:MTLRegionMake2D(column, row, 1, 1) mipmapLevel:0];
        BOOL matches = YES;
        for (NSUInteger channel = 0; channel < 4; channel++) {
            int difference = (int)((actual >> (channel * 8)) & 255) - (int)((colors[quadrant] >> (channel * 8)) & 255);
            if (abs(difference) > 8) matches = NO;
        }
        if (!matches) {
            fprintf(stderr, "Geometry mismatch: %lux%lu input %.1f output %.1f quadrant %lu: %08x != %08x\n",
                (unsigned long)width, (unsigned long)height, inputRotation, videoRotation,
                (unsigned long)quadrant, actual, colors[quadrant]);
            return NO;
        }
    }
    printf("PASS: geometry %lux%lu, input %.1f°, output %.1f°\n", (unsigned long)width, (unsigned long)height, inputRotation, videoRotation);
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 2;
        NSString *project = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]
            encoding:NSUTF8StringEncoding error:NULL];
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!project || !device) { fputs("Project fixture or Metal device unavailable\n", stderr); return 1; }
        NSUInteger iterations = argc > 2 ? strtoul(argv[2], NULL, 10) : 100;
        if (iterations == 0 || iterations > 10000) return 2;
        startLogger("/tmp/gyroflow-metal-tests.log");
        printf("Metal device: %s\n", device.name.UTF8String);
        if (!runFormat(device, project.UTF8String, MTLPixelFormatBGRA8Unorm, "BGRA8", 1, iterations, 64, 32) ||
            !runFormat(device, project.UTF8String, MTLPixelFormatRGBA16Float, "RGBAf16", 2, iterations, 64, 32) ||
            !runFormat(device, project.UTF8String, MTLPixelFormatRGBA32Float, "RGBAf", 4, iterations, 64, 32)) return 1;
        for (NSNumber *rotation in @[@90, @270]) {
            if (!runGeometry(device, project.UTF8String, 32, 64, rotation.doubleValue, rotation.doubleValue) ||
                !runGeometry(device, project.UTF8String, 16, 32, rotation.doubleValue, rotation.doubleValue) ||
                !runGeometry(device, project.UTF8String, 64, 32, rotation.doubleValue, 0)) return 1;
        }
        NSMutableDictionary *portrait = [NSJSONSerialization JSONObjectWithData:[project dataUsingEncoding:NSUTF8StringEncoding]
            options:NSJSONReadingMutableContainers error:NULL];
        portrait[@"video_info"][@"width"] = @32;
        portrait[@"video_info"][@"height"] = @64;
        portrait[@"calibration_data"][@"calib_dimension"] = @{@"w": @32, @"h": @64};
        portrait[@"calibration_data"][@"orig_dimension"] = @{@"w": @32, @"h": @64};
        portrait[@"calibration_data"][@"fisheye_params"][@"camera_matrix"] = @[@[@32,@0,@16],@[@0,@32,@32],@[@0,@0,@1]];
        NSString *portraitProject = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:portrait options:0 error:NULL] encoding:NSUTF8StringEncoding];
        if (!runGeometry(device, portraitProject.UTF8String, 32, 64, 0, 0)) return 1;
        if (argc > 3 && strcmp(argv[3], "--4k") == 0) {
            if (!runFormat(device, project.UTF8String, MTLPixelFormatRGBA16Float, "RGBAf16", 2, iterations, 3840, 2160)) return 1;
        }
        trashCache();
    }
    return 0;
}

