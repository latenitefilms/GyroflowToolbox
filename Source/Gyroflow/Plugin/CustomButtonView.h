//
//  CustomButtonView.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import <Cocoa/Cocoa.h>
#import <FxPlug/FxPlugSDK.h>

@protocol CustomButtonViewParentPlugin <NSObject>
- (void)customButtonViewPressed:(UInt32)buttonID;
@end

@interface CustomButtonView : NSView
{
    __weak id<CustomButtonViewParentPlugin> _parentPlugin;
    UInt32 _buttonID;
}

- (instancetype)initWithParentPlugin:(id)parentPlugin
                            buttonID:(UInt32)buttonID
                         buttonTitle:(NSString*)buttonTitle;
@end
