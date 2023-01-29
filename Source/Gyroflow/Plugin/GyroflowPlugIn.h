//
//  GyroflowPlugIn.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

#import <Foundation/Foundation.h>
#import <FxPlug/FxPlugSDK.h>

@interface GyroflowPlugIn : NSObject <FxTileableEffect> {    
    //---------------------------------------------------------
    // Cached Custom Views:
    //---------------------------------------------------------
    NSView* launchGyroflowView;
    NSView* importGyroflowProjectView;
    NSView* reloadGyroflowProjectView;
    NSView* loadLastGyroflowProjectView;
}
@property (assign) id<PROAPIAccessing> apiManager;
@end
