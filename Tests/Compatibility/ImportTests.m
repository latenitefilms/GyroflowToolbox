#import "GyroflowPlugIn.h"

@interface GyroflowPlugIn (ImportTests)
- (void)importDroppedClip:(NSString *)xml;
- (void)importMediaOrMatchingProjectAtURL:(NSURL *)url completionHandler:(void (^)(void))completion;
- (NSModalResponse)chooseImportForMediaURL:(NSURL *)mediaURL projectURL:(NSURL *)projectURL;
- (void)buttonReloadGyroflowProject;
- (NSString *)preparedGyroflowProjectAtURL:(NSURL *)projectURL;
@end

@interface ReloadTestHost : NSObject <PROAPIAccessing, FxCustomParameterActionAPI_v4>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *values;
@property (nonatomic) BOOL actionOpen;
@property (nonatomic) BOOL denyParameters;
@property (nonatomic) NSUInteger starts;
@property (nonatomic) NSUInteger ends;
@property (nonatomic) NSUInteger writes;
@end

@implementation ReloadTestHost
- (id)apiForProtocol:(Protocol *)protocol {
    if (protocol == @protocol(FxCustomParameterActionAPI_v4)) return self;
    return self.actionOpen && !self.denyParameters ? self : nil;
}
- (void)startAction:(id)sender { self.actionOpen = YES; self.starts++; }
- (void)endAction:(id)sender {
    NSCAssert(self.actionOpen, @"Reload ended an inactive action");
    self.actionOpen = NO;
    self.ends++;
}
- (CMTime)currentTime { return kCMTimeZero; }
- (BOOL)getStringParameterValue:(NSString **)value fromParameter:(UInt32)identifier {
    *value = self.values[@(identifier)];
    return YES;
}
- (BOOL)setStringParameterValue:(NSString *)value toParameter:(UInt32)identifier {
    NSCAssert(self.actionOpen, @"Reload wrote outside its host action");
    self.values[@(identifier)] = value;
    self.writes++;
    return YES;
}
@end

/// Records the real drop routing without reading footage or presenting modal UI.
@interface ImportTestPlugin : GyroflowPlugIn
@property (nonatomic, strong) NSURL *importedMedia;
@property (nonatomic, strong) NSURL *importedProject;
@property (nonatomic) NSModalResponse choice;
@property (nonatomic) NSUInteger choices;
@property (nonatomic, copy) NSString *preparedProject;
@property (nonatomic) NSUInteger preparations;
@property (nonatomic) BOOL reloaded;
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
- (NSString *)preparedGyroflowProjectAtURL:(NSURL *)projectURL {
    self.preparations++;
    return self.preparedProject;
}
- (void)showSuccessfullyReloadedAlert { self.reloaded = YES; }
- (void)showAlertWithMessage:(NSString *)message info:(NSString *)info { }
@end

static void testReloadPreparation(NSURL *projectURL) {
    NSError *error = nil;
    NSData *bookmark = [projectURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                              includingResourceValuesForKeys:nil
                                           relativeToURL:nil error:&error];
    NSCAssert(bookmark && !error, @"%@", error);
    for (NSNumber *succeeds in @[@YES, @NO]) {
        ReloadTestHost *host = [ReloadTestHost new];
        host.values = [@{
            @(kCB_GyroflowProjectBookmarkData): [bookmark base64EncodedStringWithOptions:0],
            @(kCB_GyroflowProjectData): @"previous project"
        } mutableCopy];
        ImportTestPlugin *plugin = [ImportTestPlugin new];
        plugin.apiManager = host;
        plugin.preparedProject = succeeds.boolValue ? @"recovered embedded project" : nil;
        [plugin buttonReloadGyroflowProject];
        NSCAssert(plugin.preparations == 1, @"Reload must use the Rust project recovery path");
        NSCAssert(host.starts == 1 && host.ends == 1 && !host.actionOpen, @"Reload left the action open");
        if (succeeds.boolValue) {
            NSString *stored = [[NSString alloc] initWithData:[[NSData alloc]
                initWithBase64EncodedString:host.values[@(kCB_GyroflowProjectData)] options:0] encoding:NSUTF8StringEncoding];
            NSCAssert([stored isEqual:plugin.preparedProject] && plugin.reloaded, @"Reload did not store recovered motion data");
        } else {
            NSCAssert(host.writes == 0 && !plugin.reloaded, @"Failed or cancelled recovery changed the effect");
        }
        host.denyParameters = YES;
        [plugin buttonReloadGyroflowProject];
        NSCAssert(host.starts == 2 && host.ends == 2 && !host.actionOpen, @"Missing parameter API left the action open");
    }
}

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
        testReloadPreparation(project);
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
    puts("PASS: media/project selection, broken adjacent projects, reload recovery and cancellation");
}
