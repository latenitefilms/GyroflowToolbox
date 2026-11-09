#import "GyroflowAnalysis.h"
#import "GyroflowActions.h"
#import "MetalDeviceCache.h"
#import "GyroflowAnalysisImage.h"

BOOL GyroflowAnalysisError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
        userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

NSDictionary *GyroflowBridgeResult(const char *response, NSError **error) {
    if (!response) { GyroflowAnalysisError(error, @"Gyroflow did not return a result."); return nil; }
    NSData *data = [NSData dataWithBytes:response length:strlen(response)];
    freeCString((char *)response);
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![value isKindOfClass:NSDictionary.class]) {
        GyroflowAnalysisError(error, @"Gyroflow returned an invalid result."); return nil;
    }
    if (![value[@"ok"] boolValue]) {
        GyroflowAnalysisError(error, value[@"error"] ?: @"Gyroflow could not complete the operation."); return nil;
    }
    return value[@"result"];
}

@interface GyroflowAnalysis ()
@property (nonatomic, weak) GyroflowPlugIn *plugin;
@property (nonatomic, strong) NSLock *lock;
@property (atomic) BOOL cancelled;
@property (atomic) uint64_t session;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *original;
@property (nonatomic, copy) NSString *parameters;
@property (nonatomic, copy) NSString *mode;
@property (nonatomic) CMTime timelineOrigin;
@property (nonatomic) CMTimeRange range;
@property (nonatomic) CMTime frameDuration;
@property (nonatomic) CMTime lastFrameTime;
@property (nonatomic) CMTime firstMediaTime;
@property (nonatomic) CMTime firstAnalysisTime;
@property (nonatomic) BOOL failed;
@property (nonatomic, strong) GyroflowAnalysisImage *imageConverter;
@property (nonatomic) uint64_t deviceRegistryID;
@property (nonatomic, copy) NSDictionary *frameLayout;
@property (nonatomic) CGSize textureSize;
@end

@implementation GyroflowAnalysis

- (instancetype)initWithPlugin:(GyroflowPlugIn *)plugin {
    if ((self = [super init])) { _plugin = plugin; _lock = [NSLock new]; }
    return self;
}

- (void)dealloc { releaseToolboxAnalysis(_session); }

/// The lifecycle lock must be held. Failed setup does not rely on a host cleanup callback.
- (void)releaseAnalysisResources {
    releaseToolboxAnalysis(self.session);
    self.session = 0;
    self.frameLayout = nil;
    self.imageConverter = nil;
    self.source = nil;
    self.original = nil;
    self.parameters = nil;
}

- (void)cancel {
    self.cancelled = YES;
    cancelToolboxAnalysis(self.session);
}

- (BOOL)startMode:(NSString *)mode project:(NSString *)project originalProject:(NSString *)original
      parameters:(NSString *)parameters error:(NSError **)error {
    id<FxAnalysisAPI> api = [self.plugin.apiManager apiForProtocol:@protocol(FxAnalysisAPI)];
    if (!api) return GyroflowAnalysisError(error, @"This host does not provide background analysis.");
    FxAnalysisState state = [api analysisStateForEffect];
    if (state == kFxAnalysisState_AnalysisRequested || state == kFxAnalysisState_AnalysisStarted)
        return GyroflowAnalysisError(error, @"This clip is already being analysed.");
    [self.lock lock];
    [self releaseAnalysisResources];
    self.source = project;
    self.original = original;
    self.parameters = parameters;
    self.mode = mode;
    self.cancelled = NO;
    self.failed = NO;
    self.lastFrameTime = kCMTimeInvalid;
    self.firstMediaTime = kCMTimeInvalid;
    self.firstAnalysisTime = kCMTimeInvalid;
    [self.lock unlock];
    BOOL started = [api startForwardAnalysis:kFxAnalysisLocation_GPU error:error];
    if (!started) {
        [self.lock lock];
        [self releaseAnalysisResources];
        [self.lock unlock];
    }
    return started;
}

- (BOOL)desiredAnalysisTimeRange:(CMTimeRange *)desiredRange forInputWithTimeRange:(CMTimeRange)inputRange
                          error:(NSError **)error {
    if (!CMTIMERANGE_IS_VALID(inputRange) || CMTimeCompare(inputRange.duration, kCMTimeZero) <= 0)
        return GyroflowAnalysisError(error, @"The clip has no frames to analyse.");
    *desiredRange = inputRange;
    return YES;
}

- (BOOL)setupAnalysisForTimeRange:(CMTimeRange)range frameDuration:(CMTime)duration error:(NSError **)error {
    [self.lock lock];
    BOOL succeeded = NO;
    @try {
        if (self.cancelled || !self.source.length) return GyroflowAnalysisError(error, @"Analysis cancelled.");
        releaseToolboxAnalysis(self.session);
        self.session = 0;
        self.range = range;
        self.frameDuration = duration;
        id<FxTimingAPI_v4> timing = [self.plugin.apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
        CMTime start = kCMTimeInvalid, timelineOrigin = kCMTimeInvalid;
        [timing startTimeForEffect:&start];
        [timing timelineTime:&timelineOrigin fromInputTime:start];
        self.timelineOrigin = timelineOrigin;
        CMTime rangeStart = kCMTimeInvalid, rangeEnd = kCMTimeInvalid;
        [timing timelineTime:&rangeStart fromInputTime:range.start];
        [timing timelineTime:&rangeEnd fromInputTime:CMTimeRangeGetEnd(range)];
        if (!CMTIME_IS_NUMERIC(timelineOrigin) || !CMTIME_IS_NUMERIC(rangeStart) || !CMTIME_IS_NUMERIC(rangeEnd))
            return GyroflowAnalysisError(error, @"Final Cut Pro could not provide the clip timing for analysis.");
        NSDictionary *request = @{@"mode": self.mode,
            @"start_ms": @(MAX(0, CMTimeGetSeconds(CMTimeSubtract(rangeStart, timelineOrigin)) * 1000)),
            @"end_ms": @(CMTimeGetSeconds(CMTimeSubtract(rangeEnd, timelineOrigin)) * 1000)};
        NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
        if (!data) return NO;
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSDictionary *result = GyroflowBridgeResult(beginToolboxAnalysis(self.source.UTF8String, self.original.UTF8String,
            self.parameters.UTF8String, json.UTF8String), error);
        if (!result) { self.failed = YES; return NO; }
        self.session = [result[@"session"] unsignedLongLongValue];
        if (self.cancelled) return GyroflowAnalysisError(error, @"Analysis cancelled.");
        succeeded = YES;
        return YES;
    } @finally {
        if (!succeeded) [self releaseAnalysisResources];
        [self.lock unlock];
    }
}

- (BOOL)analyzeFrame:(FxImageTile *)frame atTime:(CMTime)frameTime error:(NSError **)error {
    [self.lock lock];
    @try {
        if (self.cancelled || self.failed || !self.session)
            return GyroflowAnalysisError(error, @"Analysis cancelled.");
        id<FxTimingAPI_v4> timing = [self.plugin.apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
        CMTime timelineTime = kCMTimeInvalid;
        [timing timelineTime:&timelineTime fromInputTime:frameTime];
        CMTime timestamp = CMTimeConvertScale(CMTimeSubtract(timelineTime, self.timelineOrigin), 1000000,
            kCMTimeRoundingMethod_RoundHalfAwayFromZero);
        if (!CMTIME_IS_NUMERIC(timestamp)) {
            self.failed = YES; return GyroflowAnalysisError(error, @"The analysis frame has no valid timestamp.");
        }
        // Never fit source gyro samples against a stretched or reversed timeline clock.
        // Comparing elapsed times permits nonzero source timecodes and ordinary clip trims.
        if (CMTIME_IS_NUMERIC(frame.mediaTime)) {
            if (!CMTIME_IS_NUMERIC(self.firstMediaTime)) {
                self.firstMediaTime = frame.mediaTime;
                self.firstAnalysisTime = timestamp;
            } else {
                double mediaElapsed = CMTimeGetSeconds(CMTimeSubtract(frame.mediaTime, self.firstMediaTime));
                double analysisElapsed = CMTimeGetSeconds(CMTimeSubtract(timestamp, self.firstAnalysisTime));
                double tolerance = MAX(0.002, fabs(CMTimeGetSeconds(self.frameDuration)));
                if (fabs(mediaElapsed - analysisElapsed) > tolerance) {
                    self.failed = YES;
                    return GyroflowAnalysisError(error, @"Analyse the clip at its original speed. To retime the result, apply Gyroflow Toolbox inside a compound clip and retime the compound clip.");
                }
            }
        }
        self.lastFrameTime = frameTime;
        int needed = toolboxWantsAnalysisFrame(self.session, timestamp.value);
        if (needed < 0) return GyroflowAnalysisError(error, @"Analysis cancelled.");
        if (!needed) return YES;
        id<MTLDevice> device = [[MetalDeviceCache deviceCache] deviceWithRegistryID:frame.deviceRegistryID];
        id<MTLTexture> texture = [frame metalTextureForDevice:device];
        if (!device || !texture) {
            self.failed = YES;
            return GyroflowAnalysisError(error, @"The Metal GPU is unavailable. Try analysing the clip again.");
        }
        if (!self.imageConverter || self.deviceRegistryID != frame.deviceRegistryID) {
            self.imageConverter = [[GyroflowAnalysisImage alloc] initWithDevice:device];
            self.deviceRegistryID = frame.deviceRegistryID;
        }
        CGSize textureSize = CGSizeMake(texture.width, texture.height);
        if (!self.frameLayout || !CGSizeEqualToSize(self.textureSize, textureSize)) {
            self.frameLayout = GyroflowBridgeResult(toolboxAnalysisFrameLayout(self.session,
                (uint32_t)texture.width, (uint32_t)texture.height), error);
            self.textureSize = textureSize;
        }
        NSDictionary *layout = self.frameLayout;
        if (!layout) { self.failed = YES; return NO; }
        NSData *pixels = [self.imageConverter convertTexture:texture topDown:frame.imageOrigin == kFxImageOrigin_TOP_LEFT
            layout:layout error:error];
        if (!pixels) { self.failed = YES; return NO; }
        NSUInteger width = [layout[@"width"] unsignedIntegerValue], height = [layout[@"height"] unsignedIntegerValue];
        NSDictionary *result = GyroflowBridgeResult(feedToolboxAnalysis(self.session, timestamp.value,
            (uint32_t)width, (uint32_t)height, width, pixels.bytes, pixels.length), error);
        self.failed = result == nil;
        self.lastFrameTime = frameTime;
        return !self.failed;
    } @catch (NSException *exception) {
        self.failed = YES;
        return GyroflowAnalysisError(error, exception.reason ?: @"The Metal GPU could not prepare an analysis frame.");
    } @finally { [self.lock unlock]; }
}

- (BOOL)cleanupAnalysis:(NSError **)error {
    [self.lock lock];
    @try {
        id<FxAnalysisAPI> api = [self.plugin.apiManager apiForProtocol:@protocol(FxAnalysisAPI)];
        FxAnalysisState state = [api analysisStateForEffect];
        BOOL interrupted = state == kFxAnalysisState_AnalysisInterrupted;
        BOOL reachedEnd = CMTIME_IS_NUMERIC(self.lastFrameTime) &&
            CMTimeCompare(CMTimeAdd(self.lastFrameTime, self.frameDuration), CMTimeRangeGetEnd(self.range)) >= 0;
        if (self.cancelled || self.failed || interrupted || !self.session) return YES;
        if (!reachedEnd && state != kFxAnalysisState_AnalysisCompleted)
            return GyroflowAnalysisError(error, @"Analysis stopped before reaching the end of the clip. The existing stabilisation has been kept.");
        NSDictionary *result = GyroflowBridgeResult(finishToolboxAnalysis(self.session), error);
        if (!result) return NO;
        if (self.cancelled) return YES;
        // Do not replace a project the user imported or edited while this job was running.
        if (![self.plugin commitToolboxProject:result[@"project"] expectedProject:self.original refreshControls:NO error:error]) return NO;
        [self.plugin applyToolboxControlValues:result[@"controls"]];
        return YES;
    } @finally {
        [self releaseAnalysisResources];
        [self.lock unlock];
    }
}
@end
