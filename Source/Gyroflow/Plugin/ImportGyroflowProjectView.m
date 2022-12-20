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
        _apiManager = apiManager;
        
        //---------------------------------------------------------
        // The NSView should automatically re-size to the size
        // of its parent view:
        //---------------------------------------------------------
        self.autoresizingMask = NSViewWidthSizable;
        
        //---------------------------------------------------------
        // Add the "Import Gyroflow Project" button:
        //---------------------------------------------------------
        NSButton *button = [[NSButton alloc]initWithFrame:NSMakeRect(-118, 0, 180, 30)]; // x y w h
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setBezelStyle: NSBezelStyleRounded];
        button.layer.backgroundColor = [NSColor colorWithCalibratedRed:66 green:66 blue:66 alpha:1].CGColor;
        button.layer.shadowColor = [NSColor blackColor].CGColor;
        [button setBordered:YES];
        [button setTitle:@"Import Gyroflow Project"];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed)];
        [button setAutoresizingMask: NSViewMinXMargin];
        
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
    
    NSLog(@"[Gyroflow Toolbox] Successfully deallocated ImportGyroflowProjectView.");
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
        NSLog(@"[Gyroflow Toolbox] Unable to retrieve FxCustomParameterActionAPI_v4 in selectFileButtonPressed.");
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
    if (result == NSModalResponseOK) {
        NSArray *urls = [panel URLs];
        for (id url in urls) {
            //---------------------------------------------------------
            // Start accessing security scoped resource:
            //---------------------------------------------------------
            BOOL startedOK = [url startAccessingSecurityScopedResource];
            
            if (startedOK == NO) {
                NSLog(@"[Gyroflow Toolbox] ERROR - Failed to startAccessingSecurityScopedResource.");
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
                NSLog(@"[Gyroflow Toolbox] ERROR - Bookmark Error: %@", [bookmarkError localizedDescription]);
                return;
            } else if (bookmark == nil) {
                NSLog(@"[Gyroflow Toolbox] ERROR - Bookmark Data is nil. This shouldn't happen.");
                return;
            } else {
                //NSLog(@"[Gyroflow Toolbox] Bookmark created successfully for: %@", [url path]);
                
                NSString *selectedGyroflowProjectFile            = [[url lastPathComponent] stringByDeletingPathExtension];
                NSString *selectedGyroflowProjectPath            = [url path];
                NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
                                
                //---------------------------------------------------------
                // Read the Gyroflow Project Data from File:
                //---------------------------------------------------------
                NSError *readError = nil;
                NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
                if (readError != nil) {
                    NSLog(@"[Gyroflow Toolbox] Failed to read Gyroflow Project File due to: %@", readError.localizedDescription);
                }
                
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
                    NSLog(@"[Gyroflow Toolbox] Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'.");
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
            }
            
            //---------------------------------------------------------
            // Stop accessing security scoped resource:
            //---------------------------------------------------------
            [url stopAccessingSecurityScopedResource];
        }
    }    
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

