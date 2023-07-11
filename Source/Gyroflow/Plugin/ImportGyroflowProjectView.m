//
//  ImportGyroflowProjectView.m
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 20/12/2022.
//

#import "ImportGyroflowProjectView.h"
#import "GyroflowConstants.h"

#import <FxPlug/FxPlugSDK.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation ImportGyroflowProjectView {
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
        [button setTitle:@"Import Project"];
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
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen."];
        return;
    }
     
    //---------------------------------------------------------
    // Setup an NSOpenPanel:
    //---------------------------------------------------------
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    
    //---------------------------------------------------------
    // Limit the file type to .gyroflow files:
    //---------------------------------------------------------
    UTType *gyroflowExtension       = [UTType typeWithFilenameExtension:@"gyroflow"];
    NSArray *allowedContentTypes    = [NSArray arrayWithObject:gyroflowExtension];
    [panel setAllowedContentTypes:allowedContentTypes];

    //---------------------------------------------------------
    // Open the panel:
    //---------------------------------------------------------
    NSModalResponse result = [panel runModal];
    if (result != NSModalResponseOK) {
        return;
    }

    //---------------------------------------------------------
    // Start accessing security scoped resource:
    //---------------------------------------------------------
    NSURL *url = [panel URL];
    BOOL startedOK = [url startAccessingSecurityScopedResource];
    if (startedOK == NO) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Failed to startAccessingSecurityScopedResource. This shouldn't happen."];
        return;
    }

    //---------------------------------------------------------
    // Create a Security Scope Bookmark, so we can reload
    // later:
    //---------------------------------------------------------
    NSError *bookmarkError = nil;
    NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
    NSData *bookmark = [url bookmarkDataWithOptions:bookmarkOptions
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&bookmarkError];
    
    if (bookmarkError != nil) {
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]]];
        return;
    } else if (bookmark == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Bookmark data is nil. This shouldn't happen."];
        return;
    }
    
    NSString *selectedGyroflowProjectFile            = [[url lastPathComponent] stringByDeletingPathExtension];
    NSString *selectedGyroflowProjectPath            = [url path];
    NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
                    
    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
    if (readError != nil) {
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to read Gyroflow Project File due to:\n\n%@", [readError localizedDescription]]];
        return;
    }
                    
    //---------------------------------------------------------
    // Make sure there's Processed Gyro Data in the Gyroflow
    // Project Data:
    //---------------------------------------------------------
    /*
    if (![selectedGyroflowProjectData containsString:@"integrated_quaternions"]) {
        [self showAlertWithMessage:@"Processed Gyro Data Not Found." info:@"The Gyroflow file you imported doesn't seem to contain any processed gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including processed gyro data)' option."];
        return;
    }
    */
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil)
    {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen."];
        return;
    }

    //---------------------------------------------------------
    // Update 'Gyroflow Project Path':
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_GyroflowProjectPath];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectPath toParameter:kCB_GyroflowProjectPath];
    [paramSetAPI setParameterFlags:kFxParameterFlag_HIDDEN toParameter:kCB_GyroflowProjectPath];
    
    //---------------------------------------------------------
    // Update 'Gyroflow Project Bookmark Data':
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_GyroflowProjectBookmarkData];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectBookmarkData toParameter:kCB_GyroflowProjectBookmarkData];
    [paramSetAPI setParameterFlags:kFxParameterFlag_HIDDEN toParameter:kCB_GyroflowProjectBookmarkData];
    
    //---------------------------------------------------------
    // Update 'Gyroflow Project Data':
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectData toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setParameterFlags:kFxParameterFlag_HIDDEN toParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Update 'Loaded Gyroflow Project' Text Box:
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_LoadedGyroflowProject];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];
    [paramSetAPI setParameterFlags:kFxParameterFlag_DISABLED | kFxParameterFlag_NOT_ANIMATABLE toParameter:kCB_LoadedGyroflowProject];
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Stop accessing security scoped resource:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // Show Victory Message:
    //---------------------------------------------------------
    [self showAlertWithMessage:@"Success!" info:@"The Gyroflow Project has been successfully imported.\n\nYou can now adjust the FOV, Smoothness and Lens Correction as required."];
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

