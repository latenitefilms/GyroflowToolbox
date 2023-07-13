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
@implementation GyroflowParameters

@synthesize uniqueIdentifier;
@synthesize gyroflowPath;
@synthesize gyroflowData;
@synthesize timestamp;
@synthesize fov;
@synthesize smoothness;
@synthesize lensCorrection;

@synthesize horizonLock;
@synthesize horizonRoll;
@synthesize positionOffsetX;
@synthesize positionOffsetY;
@synthesize inputRotation;
@synthesize videoRotation;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)dealloc {
    [uniqueIdentifier release];
    [gyroflowPath release];
    [gyroflowData release];
    [timestamp release];
    [fov release];
    [smoothness release];
    [lensCorrection release];
    
    [horizonLock release];
    [horizonRoll release];
    [positionOffsetX release];
    [positionOffsetY release];
    [inputRotation release];
    [videoRotation release];
    
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        self.uniqueIdentifier       = [decoder decodeObjectOfClass:[NSString class] forKey:@"uniqueIdentifier"];
        self.gyroflowPath           = [decoder decodeObjectOfClass:[NSString class] forKey:@"gyroflowPath"];
        self.gyroflowData           = [decoder decodeObjectOfClass:[NSString class] forKey:@"gyroflowData"];
        self.timestamp              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"timestamp"];
        self.fov                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"fov"];
        self.smoothness             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"smoothness"];
        self.lensCorrection         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"lensCorrection"];
                
        self.horizonLock            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"horizonLock"];
        self.horizonRoll            = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"horizonRoll"];
        self.positionOffsetX        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"positionOffsetX"];
        self.positionOffsetY        = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"positionOffsetY"];
        self.inputRotation          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"inputRotation"];
        self.videoRotation          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"videoRotation"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:uniqueIdentifier  forKey:@"uniqueIdentifier"];
    [encoder encodeObject:gyroflowPath      forKey:@"gyroflowPath"];
    [encoder encodeObject:gyroflowData      forKey:@"gyroflowData"];
    [encoder encodeObject:timestamp         forKey:@"timestamp"];
    [encoder encodeObject:fov               forKey:@"fov"];
    [encoder encodeObject:smoothness        forKey:@"smoothness"];
    [encoder encodeObject:lensCorrection    forKey:@"lensCorrection"];
    
    [encoder encodeObject:horizonLock       forKey:@"horizonLock"];
    [encoder encodeObject:horizonRoll       forKey:@"horizonRoll"];
    [encoder encodeObject:positionOffsetX   forKey:@"positionOffsetX"];
    [encoder encodeObject:positionOffsetY   forKey:@"positionOffsetY"];
    [encoder encodeObject:inputRotation     forKey:@"inputRotation"];
    [encoder encodeObject:videoRotation     forKey:@"videoRotation"];
}

@end
