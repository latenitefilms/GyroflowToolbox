//
//  GyroflowParameters.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Plugin Parameters:
//---------------------------------------------------------
@interface GyroflowParameters : NSObject <NSCoding, NSSecureCoding> {
    NSNumber *frameToRender;
    NSNumber *frameRate;
    NSString *gyroflowFile;
    NSNumber *fov;
    NSNumber *smoothness;
    NSNumber *lensCorrection;
}

@property (nonatomic, copy) NSNumber *frameToRender;
@property (nonatomic, copy) NSNumber *frameRate;
@property (nonatomic, copy) NSString *gyroflowFile;
@property (nonatomic, copy) NSNumber *fov;
@property (nonatomic, copy) NSNumber *smoothness;
@property (nonatomic, copy) NSNumber *lensCorrection;

@end
