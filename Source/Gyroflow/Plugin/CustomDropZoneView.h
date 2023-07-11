//
//  CustomButtonView.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import <Cocoa/Cocoa.h>
#import <FxPlug/FxPlugSDK.h>

@interface CustomDropZoneView : NSView <NSDraggingDestination>
{
    id<PROAPIAccessing> _apiManager;
    id _parentPlugin;
    int _buttonID;
}

- (instancetype)initWithAPIManager:(id<PROAPIAccessing>)apiManager
                 parentPlugin:(id)parentPlugin
                     buttonID:(UInt32)buttonID
                  buttonTitle:(NSString*)buttonTitle;
@end
