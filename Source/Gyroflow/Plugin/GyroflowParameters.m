//
//  GyroflowParameters.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Import Headers:
//---------------------------------------------------------
#import <Foundation/Foundation.h>
#import "GyroflowParameters.h"

//---------------------------------------------------------
// Plugin Parameters Object:
//---------------------------------------------------------
static NSString * const kUniqueIdentifier       = @"uniqueIdentifier";
static NSString * const kGyroflowPath           = @"gyroflowPath";
static NSString * const kGyroflowData           = @"gyroflowData";
static NSString * const kTimestamp              = @"timestamp";
static NSString * const kFov                    = @"fov";
static NSString * const kSmoothness             = @"smoothness";
static NSString * const kLensCorrection         = @"lensCorrection";
static NSString * const kHorizonLock            = @"horizonLock";
static NSString * const kHorizonRoll            = @"horizonRoll";
static NSString * const kPositionOffsetX        = @"positionOffsetX";
static NSString * const kPositionOffsetY        = @"positionOffsetY";
static NSString * const kInputRotation          = @"inputRotation";
static NSString * const kVideoRotation          = @"videoRotation";
static NSString * const kFovOverview            = @"fovOverview";
static NSString * const kDisableGyroflowStretch = @"disableGyroflowStretch";

@implementation GyroflowParameters

+ (BOOL)supportsSecureCoding { return YES; }

- (instancetype)initWithCoder:(NSCoder *)decoder {
    if ((self = [super init])) {
        _uniqueIdentifier       = [decoder decodeObjectOfClass:[NSString class] forKey:kUniqueIdentifier];

        _gyroflowPath           = [decoder decodeObjectOfClass:[NSString class] forKey:kGyroflowPath];
        _gyroflowData           = [decoder decodeObjectOfClass:[NSString class] forKey:kGyroflowData];

        _timestamp              = [decoder decodeObjectOfClass:[NSNumber class] forKey:kTimestamp];
        _fov                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:kFov];
        _smoothness             = [decoder decodeObjectOfClass:[NSNumber class] forKey:kSmoothness];
        _lensCorrection         = [decoder decodeObjectOfClass:[NSNumber class] forKey:kLensCorrection];

        _horizonLock            = [decoder decodeObjectOfClass:[NSNumber class] forKey:kHorizonLock];
        _horizonRoll            = [decoder decodeObjectOfClass:[NSNumber class] forKey:kHorizonRoll];
        _positionOffsetX        = [decoder decodeObjectOfClass:[NSNumber class] forKey:kPositionOffsetX];
        _positionOffsetY        = [decoder decodeObjectOfClass:[NSNumber class] forKey:kPositionOffsetY];
        _inputRotation          = [decoder decodeObjectOfClass:[NSNumber class] forKey:kInputRotation];
        _videoRotation          = [decoder decodeObjectOfClass:[NSNumber class] forKey:kVideoRotation];

        _fovOverview            = [decoder decodeObjectOfClass:[NSNumber class] forKey:kFovOverview];
        _disableGyroflowStretch = [decoder decodeObjectOfClass:[NSNumber class] forKey:kDisableGyroflowStretch];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.uniqueIdentifier       forKey:kUniqueIdentifier];
    [encoder encodeObject:self.gyroflowPath           forKey:kGyroflowPath];
    [encoder encodeObject:self.gyroflowData           forKey:kGyroflowData];

    [encoder encodeObject:self.timestamp              forKey:kTimestamp];
    [encoder encodeObject:self.fov                    forKey:kFov];
    [encoder encodeObject:self.smoothness             forKey:kSmoothness];
    [encoder encodeObject:self.lensCorrection         forKey:kLensCorrection];

    [encoder encodeObject:self.horizonLock            forKey:kHorizonLock];
    [encoder encodeObject:self.horizonRoll            forKey:kHorizonRoll];
    [encoder encodeObject:self.positionOffsetX        forKey:kPositionOffsetX];
    [encoder encodeObject:self.positionOffsetY        forKey:kPositionOffsetY];
    [encoder encodeObject:self.inputRotation          forKey:kInputRotation];
    [encoder encodeObject:self.videoRotation          forKey:kVideoRotation];

    [encoder encodeObject:self.fovOverview            forKey:kFovOverview];
    [encoder encodeObject:self.disableGyroflowStretch forKey:kDisableGyroflowStretch];
}

@end
