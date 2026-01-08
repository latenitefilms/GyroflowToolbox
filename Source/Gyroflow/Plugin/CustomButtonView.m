//
//  CustomButtonView.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 29/01/2023.
//

#import "CustomButtonView.h"
#import <FxPlug/FxPlugSDK.h>

@implementation CustomButtonView {
    NSButton* _button;
}

//---------------------------------------------------------
// Initialize:
//---------------------------------------------------------
- (instancetype)initWithParentPlugin:(id)parentPlugin
                            buttonID:(UInt32)buttonID
                         buttonTitle:(NSString*)buttonTitle
{
    int buttonWidth = 200;
    int buttonHeight = 32;
    
    NSRect frameRect = NSMakeRect(0, 0, buttonWidth, buttonHeight); // x y w h
    self = [super initWithFrame:frameRect];
    
    if (self != nil)
    {
        //---------------------------------------------------------
        // Cache the parent plugin & button ID:
        //---------------------------------------------------------
        _parentPlugin = parentPlugin;
        _buttonID = buttonID;
        
        //---------------------------------------------------------
        // Add the button:
        //---------------------------------------------------------
        NSButton *button = [[NSButton alloc]initWithFrame:NSMakeRect(0, 0, buttonWidth, buttonHeight)]; // x y w h
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setBezelStyle: NSBezelStyleRounded];
        button.layer.backgroundColor = [NSColor colorWithCalibratedRed:66 green:66 blue:66 alpha:1].CGColor;
        button.layer.shadowColor = [NSColor blackColor].CGColor;
        [button setBordered:YES];
        [button setTitle:buttonTitle];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed)];
        
        _button = button;
        [self addSubview:_button];
    }
    
    return self;
}

//---------------------------------------------------------
// Triggered when the button is pressed:
//---------------------------------------------------------
- (void)buttonPressed {
    [_parentPlugin customButtonViewPressed:_buttonID];
}

//---------------------------------------------------------
// Draw the NSView:
//---------------------------------------------------------
- (void)drawRect:(NSRect)dirtyRect {
    //---------------------------------------------------------
    // Draw the button:
    //---------------------------------------------------------
    [super drawRect:dirtyRect];
}

//---------------------------------------------------------
// Because custom views are hosted in an overlay window,
// the first click on them will normally just make the
// overlay window be the key window, and it will require a
// second click in order to actually tell the view to
// start responding. By returning YES from this method, the
// first click begins user interaction with the view.
//---------------------------------------------------------
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

@end

