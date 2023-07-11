//
//  GyroflowParameters.h
//  Gyroflow Toolbox
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
}

@property (nonatomic, copy) NSString *gyroflowPath;
@property (nonatomic, copy) NSString *gyroflowData;
@property (nonatomic, copy) NSNumber *timestamp;
@property (nonatomic, copy) NSNumber *fov;
@property (nonatomic, copy) NSNumber *smoothness;
@property (nonatomic, copy) NSNumber *lensCorrection;

@end
