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
    
    NSLog(@"Launch Gyroflow!");
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug."];
        return;
    }
        
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow project path:
    //---------------------------------------------------------
    NSString *existingProjectPath = nil;
    [paramGetAPI getStringParameterValue:&existingProjectPath fromParameter:kCB_GyroflowProjectPath];
    
    NSLog(@"existingProjectPath: %@", existingProjectPath);
        
    //---------------------------------------------------------
    // Open Gyroflow or the current Gyroflow Project:
    //---------------------------------------------------------
    NSString *bundleIdentifier = @"xyz.gyroflow";
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    
    NSLog(@"appURL: %@", appURL);
    if (appURL) {
        if (existingProjectPath == nil || [existingProjectPath isEqualToString:@""]) {
            NSLog(@"Just launching Gyroflow by itself.");
            [[NSWorkspace sharedWorkspace] openURL:appURL];
        } else {
            
            
            // /Applications/Gyroflow.app/Contents/MacOS/gyroflow
            
            
            
            NSLog(@"Launching Gyroflow with project: %@", existingProjectPath);
            
NSString *bundleIdentifier = @"xyz.gyroflow";
NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
NSWorkspaceOpenConfiguration *config = [[[NSWorkspaceOpenConfiguration alloc] init] autorelease];
config.arguments = @[@"--returnLastOpenProjectPath"];
[[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL configuration:config completionHandler:nil];
        }
    } else {
        [self showAlertWithMessage:@"Failed to launch Gyroflow." info:@"Please check that Gyroflow is installed in your Applications folder and try again."];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];    
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

