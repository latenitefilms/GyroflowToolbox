// Real-frame harness: external decoding is test-only; Metal texture processing uses the shipping ABI.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include "gyroflow.h"
#include <sys/resource.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 8) return 2;
        NSString *project = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:NULL];
        NSData *pixels = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        NSUInteger width = strtoul(argv[4], NULL, 10), height = strtoul(argv[5], NULL, 10);
        int64_t timestamp = strtoll(argv[6], NULL, 10);
        NSUInteger iterations = strtoul(argv[7], NULL, 10);
        if (!project || !width || !height || width > 16384 || height > 16384 ||
            !iterations || iterations > 10000 || pixels.length != width * height * 4) return 2;
        NSString *logPath = [[[NSString stringWithUTF8String:argv[3]] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"engine.log"];
        startLogger(logPath.UTF8String);
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) return 1;
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
        descriptor.storageMode = MTLStorageModeShared;
        descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
        id<MTLTexture> input = [device newTextureWithDescriptor:descriptor];
        id<MTLTexture> output = [device newTextureWithDescriptor:descriptor];
        if (!input || !output) return 1;
        [input replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:width * 4];
        const char *definitionsString = getPluginParameterDefinitions();
        NSArray *definitions = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:definitionsString length:strlen(definitionsString)] options:0 error:NULL];
        freeCString((char *)definitionsString);
        const char *defaultsString = getEngineControlDefaults(project.UTF8String);
        NSDictionary *defaults = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:defaultsString length:strlen(defaultsString)] options:0 error:NULL];
        freeCString((char *)defaultsString);
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (NSDictionary *definition in definitions) {
            if ([@[@"slider", @"toggle", @"menu"] containsObject:definition[@"kind"]]) {
                NSString *identifier = [definition[@"id"] stringValue];
                values[identifier] = defaults[identifier] ?: definition[@"default"];
            }
        }
        values[@"170"] = @0;
        NSString *parameters = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:values options:0 error:NULL] encoding:NSUTF8StringEncoding];
        const char *identifiersString = getKeyframeParameterIDs();
        NSArray *identifiers = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:identifiersString length:strlen(identifiersString)] options:0 error:NULL];
        freeCString((char *)identifiersString);
        NSMutableArray *rows = [NSMutableArray array];
        for (NSNumber *identifier in identifiers) {
            NSNumber *value = values[identifier.stringValue];
            if (!value) { fprintf(stderr, "Missing control default %u\n", identifier.unsignedIntValue); return 1; }
            [rows addObject:@[identifier, @[@[@0, value]]]];
        }
        NSString *curves = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@[@2, @0, rows, values] options:0 error:NULL] encoding:NSUTF8StringEncoding];
        // File is decoded without its display transform; supplied real fixtures all have zero rotation.
        NSDictionary *document = [NSJSONSerialization JSONObjectWithData:[project dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        double fps = [document[@"video_info"][@"fps"] doubleValue];
        if (fps <= 0) return 2;
        BOOL (^render)(int64_t) = ^BOOL(int64_t time) {
            return processFrameWithParameters("real-media", (uint32_t)width, (uint32_t)height, "BGRA8", 1,
                argv[1], project.UTF8String, time, parameters.UTF8String, curves.UTF8String,
                (__bridge void *)input, (__bridge void *)output, NULL) != 0;
        };
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent(), warmStart = 0;
        for (NSUInteger frame = 0; frame <= iterations; frame++) {
            @autoreleasepool {
                if (!render(timestamp + (int64_t)((frame % 30) * 1000000.0 / fps))) return 1;
                if (frame == 0) warmStart = CFAbsoluteTimeGetCurrent();
            }
        }
        CFAbsoluteTime finished = CFAbsoluteTimeGetCurrent();
        if (!render(timestamp)) return 1;
        NSMutableData *result = [NSMutableData dataWithLength:pixels.length];
        [output getBytes:result.mutableBytes bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
        const uint8_t *bytes = result.bytes;
        NSUInteger opaque = 0, nonzero = 0;
        for (NSUInteger pixel = 0; pixel < width * height; pixel++) {
            opaque += bytes[pixel * 4 + 3] >= 250;
            nonzero += (bytes[pixel * 4] | bytes[pixel * 4 + 1] | bytes[pixel * 4 + 2]) > 0;
        }
        if (opaque < width * height / 4 || nonzero < width * height / 4) { fputs("Render is mostly empty\n", stderr); return 1; }
        if (![result writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES]) return 1;
        struct rusage usage;
        getrusage(RUSAGE_SELF, &usage);
        printf("{\"cold_ms\":%.3f,\"warm_ms\":%.3f,\"opaque_percent\":%.2f,\"peak_rss_mb\":%.1f,\"frames\":%lu}\n",
            (warmStart - start) * 1000.0, (finished - warmStart) * 1000.0 / iterations,
            100.0 * opaque / (width * height), usage.ru_maxrss / (1024.0 * 1024.0), (unsigned long)iterations);
        trashCache();
    }
    return 0;
}
