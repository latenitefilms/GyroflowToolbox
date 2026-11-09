#import "GyroflowPlugIn.h"

@interface GyroflowPlugIn (ImportTests)
- (void)importDroppedClip:(NSString *)xml;
- (void)importMediaOrMatchingProjectAtURL:(NSURL *)url completionHandler:(void (^)(void))completion;
- (NSModalResponse)chooseImportForMediaURL:(NSURL *)mediaURL projectURL:(NSURL *)projectURL;
@end

/// Records the real drop routing without reading footage or presenting modal UI.
@interface ImportTestPlugin : GyroflowPlugIn
@property (nonatomic, strong) NSURL *importedMedia;
@property (nonatomic, strong) NSURL *importedProject;
@property (nonatomic) NSModalResponse choice;
@property (nonatomic) NSUInteger choices;
@end

@implementation ImportTestPlugin
- (NSModalResponse)chooseImportForMediaURL:(NSURL *)mediaURL projectURL:(NSURL *)projectURL {
    self.choices++;
    return self.choice;
}
- (void)importMediaWithOptionalURL:(NSURL *)url completionHandler:(void (^)(void))completion {
    self.importedMedia = url;
    if (completion) completion();
}
- (void)importGyroflowProjectWithOptionalURL:(NSURL *)url completionHandler:(void (^)(void))completion {
    self.importedProject = url;
    if (completion) completion();
}
@end

void testImportRouting(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *folder = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    NSCAssert([files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    @try {
        NSURL *media = [folder URLByAppendingPathComponent:@"GoPro Hero 6.MP4"];
        NSURL *project = [folder URLByAppendingPathComponent:@"GoPro Hero 6.gyroflow"];
        NSCAssert([@"" writeToURL:media atomically:YES encoding:NSUTF8StringEncoding error:&error], @"%@", error);
        NSCAssert([@"invalid project" writeToURL:project atomically:YES encoding:NSUTF8StringEncoding error:&error], @"%@", error);
        ImportTestPlugin *plugin = [ImportTestPlugin new];
        plugin.choice = NSAlertFirstButtonReturn;
        NSString *xml = [NSString stringWithFormat:@"<fcpxml><resources><asset><media-rep src=\"%@\"/></asset></resources></fcpxml>", media.absoluteString];
        [plugin importDroppedClip:xml];
        NSCAssert([plugin.importedMedia isEqual:media] && !plugin.importedProject,
            @"A matching broken project hijacked an explicit media import");
        NSCAssert(plugin.choices == 1, @"A matching project must offer an import choice");

        plugin.importedMedia = nil;
        plugin.choice = NSAlertSecondButtonReturn;
        __block NSUInteger completions = 0;
        [plugin importMediaOrMatchingProjectAtURL:media completionHandler:^{ completions++; }];
        NSCAssert([plugin.importedProject isEqual:project] && !plugin.importedMedia && completions == 1,
            @"Choosing the saved project must retain its original import route and finish access");

        plugin.importedProject = nil;
        plugin.choice = NSAlertThirdButtonReturn;
        [plugin importMediaOrMatchingProjectAtURL:media completionHandler:^{ completions++; }];
        NSCAssert(!plugin.importedProject && !plugin.importedMedia && completions == 2,
            @"Cancelling must leave the effect unchanged and release its caller's access");

        NSCAssert([files removeItemAtURL:project error:&error], @"%@", error);
        [plugin importMediaOrMatchingProjectAtURL:media completionHandler:^{ completions++; }];
        NSCAssert([plugin.importedMedia isEqual:media] && plugin.choices == 3 && completions == 3,
            @"Media without a matching project must import directly");
    } @finally {
        [files removeItemAtURL:folder error:nil];
    }
    puts("PASS: media/project selection, broken adjacent projects and cancellation");
}
