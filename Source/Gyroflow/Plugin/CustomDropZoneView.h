//
//  CustomButtonView.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import <Cocoa/Cocoa.h>
#import <FxPlug/FxPlugSDK.h>

@protocol CustomDropZoneViewParentPlugin <NSObject>
- (void)importDroppedMedia:(NSData*)bookmarkData;
- (void)importDroppedClip:(NSString*)fcpxmlString;
@end


@interface CustomDropZoneView : NSView <NSDraggingDestination>
{
    __weak id<CustomDropZoneViewParentPlugin> _parentPlugin;
    UInt32 _buttonID;
}

- (instancetype)initWithParentPlugin:(id)parentPlugin
                            buttonID:(UInt32)buttonID
                         buttonTitle:(NSString*)buttonTitle;
@end
