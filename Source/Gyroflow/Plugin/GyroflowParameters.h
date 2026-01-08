//
//  GyroflowParameters.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Plugin Parameters:
//---------------------------------------------------------
#import <Foundation/Foundation.h>

@interface GyroflowParameters : NSObject <NSSecureCoding>

@property (nonatomic, copy, nullable) NSString *uniqueIdentifier;
@property (nonatomic, copy, nullable) NSString *gyroflowPath;
@property (nonatomic, copy, nullable) NSString *gyroflowData;

@property (nonatomic, strong, nullable) NSNumber *timestamp;
@property (nonatomic, strong, nullable) NSNumber *fov;
@property (nonatomic, strong, nullable) NSNumber *smoothness;
@property (nonatomic, strong, nullable) NSNumber *lensCorrection;

@property (nonatomic, strong, nullable) NSNumber *horizonLock;
@property (nonatomic, strong, nullable) NSNumber *horizonRoll;
@property (nonatomic, strong, nullable) NSNumber *positionOffsetX;
@property (nonatomic, strong, nullable) NSNumber *positionOffsetY;
@property (nonatomic, strong, nullable) NSNumber *inputRotation;
@property (nonatomic, strong, nullable) NSNumber *videoRotation;

@property (nonatomic, strong, nullable) NSNumber *fovOverview;
@property (nonatomic, strong, nullable) NSNumber *disableGyroflowStretch;

@end
