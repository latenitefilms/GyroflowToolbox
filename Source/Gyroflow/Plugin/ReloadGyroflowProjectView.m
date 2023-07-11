//
//  ReloadGyroflowProjectView.m
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 20/12/2022.
//

#import "ReloadGyroflowProjectView.h"
#import "GyroflowConstants.h"

#import <FxPlug/FxPlugSDK.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ReloadGyroflowProjectView {
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
        [button setTitle:@"Reload Project"];
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
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }
    
    //---------------------------------------------------------
    // Get the encoded bookmark string:
    //---------------------------------------------------------
    NSString *encodedBookmark;
    [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_GyroflowProjectBookmarkData];
    
    //---------------------------------------------------------
    // Make sure there's actually encoded bookmark data:
    //---------------------------------------------------------
    if ([encodedBookmark isEqualToString:@""]) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"There's no previous security-scoped bookmark data found.\n\nPlease make sure you import a Gyroflow Project before attempting to reload."];
        return;
    }
    
    //---------------------------------------------------------
    // Decode the Base64 bookmark data:
    //---------------------------------------------------------
    NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                              options:0] autorelease];

    //---------------------------------------------------------
    // Resolve the decoded bookmark data into a
    // security-scoped URL:
    //---------------------------------------------------------
    NSError *bookmarkError  = nil;
    BOOL isStale            = NO;
    
    NSURL *url = [NSURL URLByResolvingBookmarkData:decodedBookmark
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&isStale
                                             error:&bookmarkError];
    
    if (bookmarkError != nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]]];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil)
    {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterSettingAPI_v5'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }

    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    [url startAccessingSecurityScopedResource];
    
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
    [url stopAccessingSecurityScopedResource];
    if (readError != nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to read Gyroflow Project file due to:\n\n%@", [readError localizedDescription]]];
        return;
    }
    
    //---------------------------------------------------------
    // Update 'Gyroflow Project Data':
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectData toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setParameterFlags:kFxParameterFlag_HIDDEN toParameter:kCB_GyroflowProjectData];
        
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Show success message:
    //---------------------------------------------------------
    [self showAlertWithMessage:@"Success!" info:@"The Gyroflow Project has been successfully reloaded from disk."];
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

