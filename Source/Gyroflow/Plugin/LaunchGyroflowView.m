//
//  LaunchGyroflowView.m
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 22/12/2022.
//

#import "LaunchGyroflowView.h"
#import "GyroflowConstants.h"

#import <FxPlug/FxPlugSDK.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation LaunchGyroflowView {
    NSButton* _cachedButton;
}

//---------------------------------------------------------
// Initialize:
//---------------------------------------------------------
- (instancetype)initWithFrame:(NSRect)frameRect
                andAPIManager:(id<PROAPIAccessing>)apiManager
{
    self = [super initWithFrame:frameRect];
    
    if (self != nil)
    {
        //---------------------------------------------------------
        // Cache the API Manager:
        //---------------------------------------------------------
        _apiManager = apiManager;
        
        //---------------------------------------------------------
        // Add the "Import Gyroflow Project" button:
        //---------------------------------------------------------
        NSButton *button = [[NSButton alloc]initWithFrame:NSMakeRect(0, 0, 130, 30)]; // x y w h
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setBezelStyle: NSBezelStyleRounded];
        button.layer.backgroundColor = [NSColor colorWithCalibratedRed:66 green:66 blue:66 alpha:1].CGColor;
        button.layer.shadowColor = [NSColor blackColor].CGColor;
        [button setBordered:YES];
        [button setTitle:@"Launch Gyroflow"];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed)];
        
        _cachedButton = button;
        [self addSubview:_cachedButton];
    }
    
    return self;
}

//---------------------------------------------------------
// Deallocates the memory occupied by the receiver:
//---------------------------------------------------------
- (void)dealloc
{
    if (_cachedButton) {
        [_cachedButton release];
    }
 
    [super dealloc];
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
// Triggered when the button is pressed:
//---------------------------------------------------------
- (void)buttonPressed {    
    NSString *bundleIdentifier = @"xyz.gyroflow";
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    if (appURL) {
        [[NSWorkspace sharedWorkspace] openURL:appURL];
    } else {
        [self showAlertWithMessage:@"Failed to launch Gyroflow." info:@"Please check that Gyroflow is installed in your Applications folder and try again."];
    }
}

//---------------------------------------------------------
// Show Alert:
//---------------------------------------------------------
- (void)showAlertWithMessage:(NSString*)message info:(NSString*)info
{
    NSAlert *alert          = [[[NSAlert alloc] init] autorelease];
    alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
    alert.alertStyle        = NSAlertStyleInformational;
    alert.messageText       = message;
    alert.informativeText   = info;
    [alert runModal];
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

