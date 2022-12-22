//
//  GyroflowPlugIn.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 10/12/2022.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

@interface GyroflowPlugIn : NSObject <FxTileableEffect> {
    NSView* launchGyroflowView;
    NSView* importGyroflowProjectView;
    NSView* reloadGyroflowProjectView;    
}
@property (assign) id<PROAPIAccessing> apiManager;
@end
