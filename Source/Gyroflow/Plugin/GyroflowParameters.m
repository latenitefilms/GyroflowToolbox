//
//  GyroflowParameters.m
//  Gyroflow Toolbox
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

@synthesize gyroflowPath;
@synthesize gyroflowData;
@synthesize timestamp;
@synthesize fov;
@synthesize smoothness;
@synthesize lensCorrection;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)dealloc {
    [gyroflowPath release];
    [gyroflowData release];
    [timestamp release];
    [fov release];
    [smoothness release];
    [lensCorrection release];
    
    [super dealloc];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        self.gyroflowPath           = [decoder decodeObjectOfClass:[NSString class] forKey:@"gyroflowPath"];
        self.gyroflowData           = [decoder decodeObjectOfClass:[NSString class] forKey:@"gyroflowData"];
        self.timestamp              = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"timestamp"];
        self.fov                    = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"fov"];
        self.smoothness             = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"smoothness"];
        self.lensCorrection         = [decoder decodeObjectOfClass:[NSNumber class] forKey:@"lensCorrection"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:gyroflowPath      forKey:@"gyroflowPath"];
    [encoder encodeObject:gyroflowData      forKey:@"gyroflowData"];
    [encoder encodeObject:timestamp         forKey:@"timestamp"];
    [encoder encodeObject:fov               forKey:@"fov"];
    [encoder encodeObject:smoothness        forKey:@"smoothness"];
    [encoder encodeObject:lensCorrection    forKey:@"lensCorrection"];
}

@end
