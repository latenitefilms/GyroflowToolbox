#import "GyroflowActions.h"
#import "GyroflowAnalysis.h"

typedef NS_ENUM(NSUInteger, AnalysisAPIVersion) {
    AnalysisAPIVersionCurrent,
    AnalysisAPIVersionLegacy,
    AnalysisAPIVersionUnavailable
};

/// Like a custom-view host, this double exposes analysis only during an action or host callback.
@interface AnalysisHost : NSObject <PROAPIAccessing, FxCustomParameterActionAPI_v4, FxAnalysisAPI_v2>
@property (nonatomic) AnalysisAPIVersion version;
@property (nonatomic) BOOL actionOpen;
@property (nonatomic) BOOL callbackOpen;
@property (nonatomic) BOOL failStart;
@property (nonatomic) FxAnalysisState state;
@property (nonatomic) NSUInteger starts;
@property (nonatomic) NSUInteger ends;
@property (nonatomic) NSUInteger analysisRequests;
@property (nonatomic) NSUInteger currentAPIRequests;
@property (nonatomic) NSUInteger legacyAPIRequests;
@end

@implementation AnalysisHost
- (id)apiForProtocol:(Protocol *)protocol {
    NSString *name = NSStringFromProtocol(protocol);
    if ([name isEqualToString:@"FxCustomParameterActionAPI_v4"]) return self;
    if ([name isEqualToString:@"FxAnalysisAPI_v2"]) {
        self.currentAPIRequests++;
        return (self.actionOpen || self.callbackOpen) && self.version == AnalysisAPIVersionCurrent ? self : nil;
    }
    if ([name isEqualToString:@"FxAnalysisAPI"]) {
        self.legacyAPIRequests++;
        return (self.actionOpen || self.callbackOpen) && self.version == AnalysisAPIVersionLegacy ? self : nil;
    }
    return nil;
}
- (void)startAction:(id)sender {
    NSCAssert(!self.actionOpen, @"Unexpected nested host action");
    self.actionOpen = YES;
    self.starts++;
}
- (void)endAction:(id)sender {
    NSCAssert(self.actionOpen, @"Unbalanced host action");
    self.actionOpen = NO;
    self.ends++;
}
- (CMTime)currentTime { return kCMTimeZero; }
- (FxAnalysisState)analysisStateForEffect {
    NSCAssert(self.actionOpen || self.callbackOpen, @"Analysis state requested outside the host context");
    return self.state;
}
- (BOOL)startForwardAnalysis:(FxAnalysisLocation)location error:(NSError **)error {
    NSCAssert(self.actionOpen, @"Analysis started after endAction:");
    NSCAssert(location == kFxAnalysisLocation_GPU, @"Analysis must request Metal frames");
    self.analysisRequests++;
    if (self.failStart) {
        if (error) *error = [NSError errorWithDomain:@"TestHost" code:17
            userInfo:@{NSLocalizedDescriptionKey: @"The host could not start this analysis job."}];
        return NO;
    }
    self.state = kFxAnalysisState_AnalysisRequested;
    return YES;
}
- (BOOL)startBackwardAnalysis:(FxAnalysisLocation)location error:(NSError **)error {
    NSCAssert(NO, @"Unexpected backwards analysis"); return NO;
}
- (BOOL)startForwardAnalysis:(FxAnalysisLocation)location ofParameter:(UInt32)identifier error:(NSError **)error {
    NSCAssert(NO, @"Expected source clip analysis, not image-well analysis"); return NO;
}
- (BOOL)startBackwardAnalysis:(FxAnalysisLocation)location ofParameter:(UInt32)identifier error:(NSError **)error {
    NSCAssert(NO, @"Unexpected backwards image-well analysis"); return NO;
}
@end

@interface AnalysisActionPlugin : GyroflowPlugIn
@property (nonatomic) BOOL failCapture;
@property (nonatomic, copy) NSString *presentedError;
@end

@implementation AnalysisActionPlugin
- (GyroflowParameters *)captureToolboxParameters:(NSError **)error {
    NSCAssert(((AnalysisHost *)self.apiManager).actionOpen, @"Capture requires a host action");
    if (self.failCapture) { GyroflowAnalysisError(error, @"Test capture failed"); return nil; }
    GyroflowParameters *parameters = [GyroflowParameters new];
    parameters.gyroflowData = @"original project";
    parameters.hostKeyframes = @"[]";
    parameters.parameterValues = @"{}";
    return parameters;
}
- (NSDictionary *)runToolboxRequest:(NSDictionary *)request parameters:(GyroflowParameters *)parameters error:(NSError **)error {
    NSCAssert([request[@"action"] isEqualToString:@"analysis_project"], @"Unexpected Rust operation");
    return @{@"project": @"configured project"};
}
- (void)presentToolboxMessage:(NSString *)title detail:(NSString *)detail {
    NSCAssert(!((AnalysisHost *)self.apiManager).actionOpen, @"Present errors after closing the host action");
    self.presentedError = detail;
}
@end

static AnalysisActionPlugin *makePlugin(AnalysisHost *host) {
    // NSObject's init avoids normal renderer startup; the production action and analysis methods run unchanged.
    AnalysisActionPlugin *plugin = [AnalysisActionPlugin new];
    plugin.apiManager = host;
    plugin.analysis = [[GyroflowAnalysis alloc] initWithPlugin:plugin];
    return plugin;
}

static void checkBalancedAction(AnalysisHost *host) {
    NSCAssert(host.starts == 1 && host.ends == 1 && !host.actionOpen, @"Host action was not balanced");
}

int main(void) {
    @autoreleasepool {
        for (NSNumber *identifier in @[@(kCB_AnalyseMotion), @(kCB_AutoSync), @(kCB_AnalyseLensDelay)]) {
            for (NSNumber *version in @[@(AnalysisAPIVersionCurrent), @(AnalysisAPIVersionLegacy)]) {
                AnalysisHost *host = [AnalysisHost new];
                host.version = version.unsignedIntegerValue;
                AnalysisActionPlugin *plugin = makePlugin(host);
                [plugin performToolboxAction:identifier.unsignedIntValue];
                NSCAssert(host.analysisRequests == 1 && !plugin.presentedError,
                    @"Supported host failed to start analysis: %@", plugin.presentedError);
                NSCAssert(host.currentAPIRequests == 1, @"Request the current analysis API first");
                NSCAssert(host.legacyAPIRequests == (host.version == AnalysisAPIVersionLegacy ? 1 : 0),
                    @"Only request the legacy API when the current version is unavailable");
                checkBalancedAction(host);
                // Cleanup runs in a separate host callback, and must negotiate the same API version.
                host.callbackOpen = YES;
                host.state = kFxAnalysisState_AnalysisInterrupted;
                [plugin.analysis setValue:@(UINT64_MAX) forKey:@"session"];
                NSError *error = nil;
                NSCAssert([plugin.analysis cleanupAnalysis:&error] && !error, @"Interrupted job cleanup failed: %@", error);
                NSCAssert(host.currentAPIRequests == 2, @"Cleanup did not request the current API");
            }
        }
        for (NSUInteger scenario = 0; scenario < 4; scenario++) {
            AnalysisHost *host = [AnalysisHost new];
            host.version = scenario == 0 ? AnalysisAPIVersionUnavailable : AnalysisAPIVersionCurrent;
            host.state = scenario == 1 ? kFxAnalysisState_AnalysisStarted : kFxAnalysisState_NotAnalyzing;
            host.failStart = scenario == 2;
            AnalysisActionPlugin *plugin = makePlugin(host);
            plugin.failCapture = scenario == 3;
            [plugin performToolboxAction:kCB_AnalyseMotion];
            checkBalancedAction(host);
            NSCAssert(plugin.presentedError.length, @"Failure did not present an error");
            NSCAssert(![plugin.presentedError containsString:@"does not provide"], @"API lookup failure is not proof of host capability");
            NSCAssert(host.analysisRequests == (scenario == 2 ? 1 : 0), @"Unexpected analysis request on failure");
            if (scenario == 2)
                NSCAssert([plugin.presentedError isEqualToString:@"The host could not start this analysis job."], @"Host error was lost");
        }
        puts("PASS: analysis action lifetime, API version negotiation, interrupted cleanup, and balanced failure paths");
    }
    return 0;
}
