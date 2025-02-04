//
//  AppDelegate.m
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 10/12/2022.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

//---------------------------------------------------------
// Show an Error Alert with Message:
//---------------------------------------------------------
- (void)showErrorAlertWithMessage:(NSString*)message info:(NSString*)info
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.alertStyle        = NSAlertStyleCritical;
    alert.messageText       = message;
    alert.informativeText   = info;
    alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

//---------------------------------------------------------
// Show an Informational Alert with Message:
//---------------------------------------------------------
- (void)showAlertWithMessage:(NSString*)message info:(NSString*)info
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.alertStyle        = NSAlertStyleInformational;
    alert.messageText       = message;
    alert.informativeText   = info;
    alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

//---------------------------------------------------------
// BUTTON: Launch Final Cut Pro
//---------------------------------------------------------
- (IBAction)pressLaunchFinalCutProButton:(NSButton *)sender {
    NSString *bundleIdentifier = @"com.apple.FinalCut";
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    if (url) {
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration new];
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:url configuration:configuration completionHandler:^(NSRunningApplication* runningApplication, NSError* error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSApplication sharedApplication] terminate:nil];
            });
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] terminate:nil];
        });
    }
}

//---------------------------------------------------------
// Check to see if we already have write access to the
// Movies folder:
//---------------------------------------------------------
- (NSURL*)getURLOfWriteableMoviesFolder {
    NSUserDefaults *userDefaults = [[[NSUserDefaults alloc] init] autorelease];
    NSData *moviesBookmarkData = [userDefaults dataForKey:@"moviesBookmarkData"];
    
    if (moviesBookmarkData == nil) {
        return NULL;
    }
    
    BOOL staleBookmark;
    NSURL *url = nil;
    NSError *bookmarkError = nil;
    url = [NSURL URLByResolvingBookmarkData:moviesBookmarkData
                                    options:NSURLBookmarkResolutionWithSecurityScope
                              relativeToURL:nil
                        bookmarkDataIsStale:&staleBookmark
                                      error:&bookmarkError];
    
    if (bookmarkError != nil) {
        return NULL;
    }
    
    if (staleBookmark) {
        return NULL;
    }
    
    if (![url startAccessingSecurityScopedResource]) {
        return NULL;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager isWritableFileAtPath:[url path]]) {
        if ([url startAccessingSecurityScopedResource]) {
            return url;
        }
        
    }
    return NULL;
}

//---------------------------------------------------------
// Install Motion Template to a specific NSURL:
//---------------------------------------------------------
- (void)installMotionTemplateToURL:(NSURL*)url {
    
    NSString *moviesPath = [url path];
    
    //---------------------------------------------------------
    // Make sure the "Movies" directory exists and is
    // accessible:
    //---------------------------------------------------------
    if(![[NSFileManager defaultManager] fileExistsAtPath:moviesPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:moviesPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [url stopAccessingSecurityScopedResource];
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:moviesPath]) {
        [url stopAccessingSecurityScopedResource];
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies' path is not writable."];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure the "Motion Templates.localized" folder
    // exists:
    //---------------------------------------------------------
    NSString* motionTemplatesPath = [moviesPath stringByAppendingString:@"/Motion Templates.localized/"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:motionTemplatesPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:motionTemplatesPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [url stopAccessingSecurityScopedResource];
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:motionTemplatesPath]) {
        [url stopAccessingSecurityScopedResource];
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/' path is not writable."];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure the "Effects.localized" folder
    // exists:
    //---------------------------------------------------------
    NSString* effectsPath = [moviesPath stringByAppendingString:@"/Motion Templates.localized/Effects.localized/"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:effectsPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:effectsPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [url stopAccessingSecurityScopedResource];
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:effectsPath]) {
        [url stopAccessingSecurityScopedResource];
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/' path is not writable."];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure the "Gyroflow Toolbox" folder exists:
    //---------------------------------------------------------
    NSString* gyroflowToolboxPath = [moviesPath stringByAppendingString:@"/Motion Templates.localized/Effects.localized/Gyroflow Toolbox/"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:gyroflowToolboxPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:gyroflowToolboxPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [url stopAccessingSecurityScopedResource];
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow Toolbox/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:gyroflowToolboxPath]) {
        [url stopAccessingSecurityScopedResource];
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow Toolbox/' path is not writable."];
        return;
    }
    NSURL *gyroflowToolboxURL = [NSURL fileURLWithPath:gyroflowToolboxPath];
    
    //---------------------------------------------------------
    // Send any old Gyroflow Toolbox to Trash:
    //---------------------------------------------------------
    if ([[NSFileManager defaultManager] fileExistsAtPath:gyroflowToolboxPath]) {
        NSError* error;
        if (![[NSFileManager defaultManager] trashItemAtURL:gyroflowToolboxURL resultingItemURL:nil error:&error]) {
            [url stopAccessingSecurityScopedResource];
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The existing '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow Toolbox/' could not be sent to Trash/Bin."];
            return;
        }
    }
    
    //---------------------------------------------------------
    // Get the "Motion Templates" path from inside the app
    // bundle:
    //---------------------------------------------------------
    NSBundle *bundlePath = [NSBundle mainBundle];
    NSString *gyroflowMotionTemplatesPath = [bundlePath pathForResource:@"Motion Templates" ofType:nil];
    
    //---------------------------------------------------------
    // Copy files:
    //---------------------------------------------------------
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:gyroflowMotionTemplatesPath toPath:gyroflowToolboxPath error:&copyError]) {
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:[copyError localizedDescription]];
    } else {
        [self showAlertWithMessage:@"Motion Template installed successfully!" info:@"You can now access the Gyroflow Toolbox Effect within Final Cut Pro."];
    }
    
    //---------------------------------------------------------
    // Create a new app-scope security-scoped bookmark for
    // future sessions:
    //---------------------------------------------------------
    NSError *bookmarkError = nil;
    NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope;
    NSData *bookmark = [url bookmarkDataWithOptions:bookmarkOptions
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&bookmarkError];
    
    if (bookmarkError != nil) {
        NSLog(@"[Gyroflow Toolbox] Bookmark Error: %@", [bookmarkError localizedDescription]);
        [self showErrorAlertWithMessage:@"Bookmark Error" info:[NSString stringWithFormat:@"The following error has occurred: %@", [bookmarkError localizedDescription]]];
        [url stopAccessingSecurityScopedResource];
        return;
    } else if (bookmark == nil) {
        [self showErrorAlertWithMessage:@"Bookmark Error" info:@"Bookmark is nil and the error message is also nil"];
        
    } else {
        NSLog(@"[Gyroflow Toolbox] Bookmark created successfully for: %@", [url path]);
    }
    
    NSUserDefaults *userDefaults = [[[NSUserDefaults alloc] init] autorelease];
    [userDefaults setObject:bookmark forKey:@"moviesBookmarkData"];
    
    //---------------------------------------------------------
    // Stop accessing Movies folder:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // Update Buttons:
    //---------------------------------------------------------
    [self updateButtons];
}

//---------------------------------------------------------
// When the "Install Motion Template" button is pressed,
// we copy our Gyroflow Toolbox Motion Template from inside
// the application bundle to the user's Motion Templates
// folder.
//---------------------------------------------------------
- (IBAction)installMotionTemplate:(id)sender {
    NSURL *writeAbleMoviesFolder = [self getURLOfWriteableMoviesFolder];
    if (writeAbleMoviesFolder == NULL) {
        //---------------------------------------------------------
        // Show popup with instructions:
        //---------------------------------------------------------
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = @"Permission Required";
        alert.informativeText   = @"Gyroflow Toolbox requires explicit permission to access your '~/Movies' folder, to install the Gyroflow Toolbox Final Cut Pro effect.\n\nPlease ensure your '~/Movies' folder is selected on the next Open Folder window to continue.";
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result){
            //---------------------------------------------------------
            // Get the user's Movies directory:
            //---------------------------------------------------------
            NSArray* moviesPaths = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory,NSUserDomainMask, YES);
            NSString* moviesPath = [moviesPaths objectAtIndex:0];
            NSURL* moviesURL = [NSURL fileURLWithPath:moviesPath];

            //---------------------------------------------------------
            // Display an open panel:
            //---------------------------------------------------------
            NSOpenPanel* panel = [NSOpenPanel openPanel];
            [panel setCanChooseDirectories:YES];
            [panel setCanCreateDirectories:YES];
            [panel setCanChooseFiles:NO];
            [panel setAllowsMultipleSelection:NO];
            [panel setDirectoryURL:moviesURL];
            [panel setPrompt:@"Grant Access"];
            [panel setMessage:@"Please click 'Grant Access' to allow access to the Movies Folder:"];
            [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result){
                if (result != NSModalResponseOK) {
                    [self showErrorAlertWithMessage:@"An error has occurred." info:@"Please make sure you select your '~/Movies' folder, and not another folder."];
                    return;
                } else {
                    NSURL *url = [panel URL];
                    [url startAccessingSecurityScopedResource];
                    [self installMotionTemplateToURL:url];
                }
            }];
        }];
    } else {
        [self installMotionTemplateToURL:writeAbleMoviesFolder];
    }
}

//---------------------------------------------------------
// Is the Motion Template Already Installed?
//---------------------------------------------------------
-(BOOL)isMotionTemplateAlreadyInstalled {
    //---------------------------------------------------------
    // Check to see if Motion Template is already installed:
    //---------------------------------------------------------
    NSUserDefaults *userDefaults = [[[NSUserDefaults alloc] init] autorelease];
    NSData *moviesBookmarkData = [userDefaults dataForKey:@"moviesBookmarkData"];
    
    if (moviesBookmarkData == nil) {
        return NO;
    }
    
    BOOL staleBookmark;
    NSURL *url = nil;
    NSError *bookmarkError = nil;
    url = [NSURL URLByResolvingBookmarkData:moviesBookmarkData
                                    options:NSURLBookmarkResolutionWithSecurityScope
                              relativeToURL:nil
                        bookmarkDataIsStale:&staleBookmark
                                      error:&bookmarkError];
    
    if (bookmarkError != nil) {
        return NO;
    }
    
    if (staleBookmark) {
        return NO;
    }
            
    [url startAccessingSecurityScopedResource];
        
    NSString* destinationPath = [[url path] stringByAppendingString:@"/Motion Templates.localized/Effects.localized/Gyroflow Toolbox/Gyroflow Toolbox/"];
        
    if(![[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
        [url stopAccessingSecurityScopedResource];
        return NO;
    }
    
    //---------------------------------------------------------
    // Get the Metadata Definition Property List path from
    // inside the app bundle:
    //---------------------------------------------------------
    NSBundle *bundlePath = [NSBundle mainBundle];
    NSString *sourcePath = [[bundlePath resourcePath] stringByAppendingString:@"/Motion Templates/Gyroflow Toolbox/"];
        
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager contentsEqualAtPath:sourcePath andPath:destinationPath]) {
        [url stopAccessingSecurityScopedResource];
        return YES;
    }
    
    [url stopAccessingSecurityScopedResource];
    return NO;
}

//---------------------------------------------------------
// Update Buttons Titles:
//---------------------------------------------------------
-(void)updateButtons {
    //---------------------------------------------------------
    // Update "Install Motion Template" button:
    //---------------------------------------------------------
    if ([self isMotionTemplateAlreadyInstalled]) {
        _buttonInstallMotionTemplate.enabled = false;
        _buttonInstallMotionTemplate.title = @"Motion Template Installed";
    } else {
        _buttonInstallMotionTemplate.enabled = true;
        _buttonInstallMotionTemplate.title = @"Install Motion Template";
    }
}

//---------------------------------------------------------
// Application did finish launching:
//---------------------------------------------------------
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    //---------------------------------------------------------
    // Update Buttons:
    //---------------------------------------------------------
    [self updateButtons];
}

//---------------------------------------------------------
// Application will terminate:
//---------------------------------------------------------
- (void)applicationWillTerminate:(NSNotification *)aNotification {
}


@end
