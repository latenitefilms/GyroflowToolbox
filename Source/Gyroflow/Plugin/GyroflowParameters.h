//
//  GyroflowParameters.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Plugin Parameters:
//---------------------------------------------------------
@interface GyroflowParameters : NSObject <NSCoding, NSSecureCoding> {    
    NSString *gyroflowPath;
    NSString *gyroflowData;
    NSNumber *timestamp;
    NSNumber *fov;
    NSNumber *smoothness;
    NSNumber *lensCorrection;
    
    NSNumber *horizonLock;
    NSNumber *horizonRoll;
    NSNumber *positionOffsetX;
    NSNumber *positionOffsetY;
    NSNumber *inputRotation;
    NSNumber *videoRotation;
}

@property (nonatomic, copy) NSString *gyroflowPath;
@property (nonatomic, copy) NSString *gyroflowData;
@property (nonatomic, copy) NSNumber *timestamp;
@property (nonatomic, copy) NSNumber *fov;
@property (nonatomic, copy) NSNumber *smoothness;
@property (nonatomic, copy) NSNumber *lensCorrection;

@property (nonatomic, copy) NSNumber *horizonLock;
@property (nonatomic, copy) NSNumber *horizonRoll;
@property (nonatomic, copy) NSNumber *positionOffsetX;
@property (nonatomic, copy) NSNumber *positionOffsetY;
@property (nonatomic, copy) NSNumber *inputRotation;
@property (nonatomic, copy) NSNumber *videoRotation;

@end
