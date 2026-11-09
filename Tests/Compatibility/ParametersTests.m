#import <Foundation/Foundation.h>
#import "GyroflowParameters.h"
#include "gyroflow.h"
#include <stddef.h>

_Static_assert(sizeof(GyroflowRenderOptions) == 48, "C and Rust options must have the same size");
_Static_assert(offsetof(GyroflowRenderOptions, integration_method) == 32, "C ABI field offset changed");

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSError *error = nil;
        NSData *archive = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        GyroflowParameters *parameters = [NSKeyedUnarchiver unarchivedObjectOfClass:GyroflowParameters.class fromData:archive error:&error];
        if (!parameters) { NSLog(@"Legacy decode failed: %@", error); return 1; }
        NSDictionary *expected = @{@"uniqueIdentifier": @"v1.3.5-fixture",
            @"gyroflowPath": @"/Legacy/clip.gyroflow", @"gyroflowData": @"{\"version\":3}",
            @"timestamp": @1234567890123LL, @"fov": @1.25, @"smoothness": @0.65,
            @"lensCorrection": @85.0, @"horizonLock": @35.0, @"horizonRoll": @-2.5,
            @"positionOffsetX": @10.0, @"positionOffsetY": @-5.0,
            @"inputRotation": @90.0, @"videoRotation": @270.0,
            @"fovOverview": @YES, @"disableGyroflowStretch": @YES};
        for (NSString *key in expected) {
            if (![[parameters valueForKey:key] isEqual:expected[key]]) {
                NSLog(@"Legacy value changed: %@", key); return 1;
            }
        }
        if (parameters.renderOptions != nil || parameters.hostKeyframes != nil || parameters.parameterValues != nil) return 1;
        GyroflowRenderOptions options = { .version = 1, .zoom_limit = 155.0,
            .integration_method = -1, .use_project_keyframes = 1 };
        parameters.renderOptions = [NSData dataWithBytes:&options length:sizeof(options)];
        parameters.hostKeyframes = @"[1,0,[[100,[[0,1],[1000000,1.5]]]]]";
        parameters.parameterValues = @"{\"100\":1.25,\"110\":0.65}";
        NSData *roundTrip = [NSKeyedArchiver archivedDataWithRootObject:parameters requiringSecureCoding:YES error:&error];
        GyroflowParameters *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:GyroflowParameters.class fromData:roundTrip error:&error];
        if (!decoded || ![decoded.renderOptions isEqual:parameters.renderOptions] ||
            ![decoded.hostKeyframes isEqual:parameters.hostKeyframes] ||
            ![decoded.parameterValues isEqual:parameters.parameterValues] ||
            decoded.timestamp.longLongValue != 1234567890123LL) return 1;
        puts("PASS: v1.3.5 archive, new options round trip, 64-bit timestamp, and C ABI layout");
    }
    return 0;
}

