#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import "GyroflowAnalysisImage.h"

static NSData *convert(GyroflowAnalysisImage *converter, id<MTLDevice> device, NSUInteger width,
                       NSUInteger height, const uint8_t *pixels, BOOL topDown, double rotation,
                       NSUInteger outputWidth, NSUInteger outputHeight) {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
        width:width height:height mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels bytesPerRow:width * 4];
    NSError *error = nil;
    NSData *result = [converter convertTexture:texture topDown:topDown layout:@{
        @"crop": @[@0, @0, @(width), @(height)], @"rotation": @(rotation),
        @"width": @(outputWidth), @"height": @(outputHeight)} error:&error];
    NSCAssert(result, @"GPU conversion failed: %@", error);
    return [result copy];
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        NSCAssert(device, @"A Metal GPU is required for this integration test.");
        GyroflowAnalysisImage *converter = [[GyroflowAnalysisImage alloc] initWithDevice:device];
        enum { width = 32, height = 16 };
        uint8_t source[width * height * 4], flipped[width * height * 4], rotated[width * height * 4];
        for (NSUInteger row = 0; row < height; row++) for (NSUInteger column = 0; column < width; column++) {
            NSUInteger index = (row * width + column) * 4;
            uint8_t value = (uint8_t)(20 + row * 8 + column * 2);
            source[index] = source[index + 1] = source[index + 2] = value; source[index + 3] = 255;
        }
        for (NSUInteger row = 0; row < height; row++)
            memcpy(flipped + row * width * 4, source + (height - 1 - row) * width * 4, width * 4);
        // Rotate source clockwise into a portrait texture, preserving all pixels.
        for (NSUInteger row = 0; row < height; row++) for (NSUInteger column = 0; column < width; column++)
            memcpy(rotated + (column * height + height - 1 - row) * 4, source + (row * width + column) * 4, 4);
        NSData *baseline = convert(converter, device, width, height, source, YES, 0, width, height);
        NSData *bottomUp = convert(converter, device, width, height, flipped, NO, 0, width, height);
        NSData *portrait = convert(converter, device, height, width, rotated, YES, 270, width, height);
        NSCAssert([baseline isEqualToData:bottomUp], @"Bottom-left frame origin changed the analysis image.");
        NSCAssert([baseline isEqualToData:portrait], @"Portrait analysis must restore native lens coordinates.");
        const uint8_t *gray = baseline.bytes;
        for (NSUInteger index = 0; index < width * height; index++)
            NSCAssert(abs((int)gray[index] - source[index * 4]) <= 1, @"GRAY8 conversion or row ordering changed pixel %lu: %u versus %u", (unsigned long)index, gray[index], source[index * 4]);
        puts("PASS: Metal GRAY8 conversion, row origins, portrait rotation, and buffer reuse");
    }
    return 0;
}
