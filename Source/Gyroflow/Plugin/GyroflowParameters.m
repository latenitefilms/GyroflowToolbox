//
//  GyroflowParameters.m
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//
#import <Foundation/Foundation.h>
#import "GyroflowParameters.h"

//---------------------------------------------------------
// Plugin Parameters Object:
//---------------------------------------------------------
@implementation GyroflowParameters

@synthesize frameToRender;
@synthesize frameRate;
@synthesize gyroflowFile;
@synthesize fov;
@synthesize smoothness;
@synthesize lensCorrection;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)dealloc {
    [frameToRender release];
    [frameRate release];
    [gyroflowFile release];
    [fov release];
    [smoothness release];
    [lensCorrection release];
    
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        self.frameToRender          = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"frameToRender"];
        self.frameRate              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"frameRate"];
        self.gyroflowFile           = [decoder decodeObjectOfClass:[NSString class] forKey:@"gyroflowFile"];
        self.fov                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"fov"];
        self.smoothness             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"smoothness"];
        self.lensCorrection         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"lensCorrection"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:frameToRender     forKey:@"frameToRender"];
    [encoder encodeObject:frameRate         forKey:@"frameRate"];
    [encoder encodeObject:gyroflowFile      forKey:@"gyroflowFile"];
    [encoder encodeObject:fov               forKey:@"fov"];
    [encoder encodeObject:smoothness        forKey:@"smoothness"];
    [encoder encodeObject:lensCorrection    forKey:@"lensCorrection"];
}

@end
