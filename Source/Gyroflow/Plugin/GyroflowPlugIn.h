//
//  GyroflowPlugIn.h
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

@interface GyroflowPlugIn : NSObject <FxTileableEffect>
@property (assign) id<PROAPIAccessing> apiManager;
@end
