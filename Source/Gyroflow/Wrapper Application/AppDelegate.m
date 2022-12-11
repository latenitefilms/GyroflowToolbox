//
//  AppDelegate.m
//  Gyroflow for Final Cut Pro
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
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

//---------------------------------------------------------
// Show an Error Alert with Message:
//---------------------------------------------------------
- (void)showAlertWithMessage:(NSString*)message info:(NSString*)info
{
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.alertStyle        = NSAlertStyleInformational;
    alert.messageText       = message;
    alert.informativeText   = info;
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (IBAction)buttonInstallMotionTemplate:(NSButton *)sender {
    //---------------------------------------------------------
    // Get the user's Movies directory:
    //---------------------------------------------------------
    NSArray* moviesPaths = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory,NSUserDomainMask, YES);
    NSString* moviesPath = [moviesPaths objectAtIndex:0];
    
    NSLog(@"[Gyroflow] moviesPath: %@", moviesPath);
    
    //---------------------------------------------------------
    // Make sure the "Movies" directory exists and is
    // accessible:
    //---------------------------------------------------------
    if(![[NSFileManager defaultManager] fileExistsAtPath:moviesPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:moviesPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:moviesPath]) {
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
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:motionTemplatesPath]) {
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
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:effectsPath]) {
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/' path is not writable."];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure the "Gyroflow" folder exists:
    //---------------------------------------------------------
    NSString* gyroflowPath = [moviesPath stringByAppendingString:@"/Motion Templates.localized/Effects.localized/Gyroflow/"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:gyroflowPath]) {
        NSError* error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:gyroflowPath withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow/' path does not exist and couldn't be created."];
            return;
        }
    }
    if (![[NSFileManager defaultManager] isWritableFileAtPath:gyroflowPath]) {
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow/' path is not writable."];
        return;
    }
    NSURL *gyroflowURL = [NSURL fileURLWithPath:gyroflowPath];
    
    //---------------------------------------------------------
    // Send any old Gyroflow to Trash:
    //---------------------------------------------------------
    if ([[NSFileManager defaultManager] fileExistsAtPath:gyroflowPath]) {
        NSError* error;
        if (![[NSFileManager defaultManager] trashItemAtURL:gyroflowURL resultingItemURL:nil error:&error]) {
            [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:@"The existing '~/Movies/Motion Templates.localized/Effects.localized/Gyroflow/' could not be sent to Trash/Bin."];
            return;
        }
    }
    
    //---------------------------------------------------------
    // Get the "Motion Templates" path from inside the app
    // bundle:
    //---------------------------------------------------------
    NSBundle *bundlePath = [NSBundle mainBundle];
    NSString *brawMotionTemplatesPath = [bundlePath pathForResource:@"Motion Templates" ofType:nil];
    
    //---------------------------------------------------------
    // Copy files:
    //---------------------------------------------------------
    NSError *copyError = nil;
    if (![[NSFileManager defaultManager] copyItemAtPath:brawMotionTemplatesPath toPath:gyroflowPath error:&copyError]) {
        [self showErrorAlertWithMessage:@"Motion Template could not be installed." info:[copyError localizedDescription]];
    } else {
        [self showAlertWithMessage:@"Motion Template installed successfully!" info:@"You can now access the Gyroflow Effect within Final Cut Pro."];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
