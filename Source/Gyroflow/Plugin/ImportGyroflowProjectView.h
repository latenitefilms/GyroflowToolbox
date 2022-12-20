//
//  ImportGyroflowProjectView.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 20/12/2022.
//

#import <Cocoa/Cocoa.h>
#import <FxPlug/FxPlugSDK.h>

@interface ImportGyroflowProjectView : NSView
{
    id<PROAPIAccessing> _apiManager;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                andAPIManager:(id<PROAPIAccessing>)apiManager;

@end
