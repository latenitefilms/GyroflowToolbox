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

/// Versioned Rust options transported with a render request; absent in v1.3.5 archives.
@property (nonatomic, copy, nullable) NSData *renderOptions;
/// Immutable Core animation snapshot; render workers never call the host's parameter APIs.
@property (nonatomic, copy, nullable) NSString *hostKeyframes;
/// Complete Rust-defined inspector payload; absent in older saved render states.
@property (nonatomic, copy, nullable) NSString *parameterValues;

@end
