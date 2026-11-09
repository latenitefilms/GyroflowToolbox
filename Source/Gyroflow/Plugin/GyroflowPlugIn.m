//
//  GyroflowPlugIn.m
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Import Headers:
//---------------------------------------------------------
#import "GyroflowPlugIn.h"
#import "GyroflowAlertFactory.h"
#import "GyroflowAnalysis.h"
#import "GyroflowActions.h"

typedef void (^BRAWCompletionHandler)(void);

/// Borrowed host APIs are only used synchronously while preparing render state.
typedef struct {
    __unsafe_unretained id<FxParameterRetrievalAPI_v6> parameters;
    __unsafe_unretained id<FxTimingAPI_v4> timing;
    CMTime timelineOrigin;
} GyroflowParameterReader;

static int readGyroflowHostParameter(void *context, uint32_t parameter, int64_t timestamp, double *value) {
    GyroflowParameterReader *reader = context;
    CMTime timelineTime = CMTimeAdd(reader->timelineOrigin, CMTimeMake(timestamp, 1000000));
    CMTime inputTime = kCMTimeInvalid;
    [reader->timing inputTime:&inputTime fromTimelineTime:timelineTime];
    return CMTIME_IS_NUMERIC(inputTime) &&
        [reader->parameters getFloatValue:value fromParameter:parameter atTime:inputTime];
}

@interface GyroflowPlugIn ()
@property (nonatomic, copy) NSArray<NSDictionary *> *engineParameterDefinitions;
@end

//---------------------------------------------------------
// Gyroflow FxPlug4 Implementation:
//---------------------------------------------------------
@implementation GyroflowPlugIn

//---------------------------------------------------------
// initWithAPIManager:
//
// This method is called when a plug-in is first loaded, and
// is a good point to conduct any checks for anti-piracy or
// system compatibility. Returning NULL means that a plug-in
// chooses not to be accessible for some reason.
//---------------------------------------------------------
- (nullable instancetype)initWithAPIManager:(id<PROAPIAccessing>)newApiManager;
{
    self = [super init];
    if (self != nil)
    {
        const char *definitions = getPluginParameterDefinitions();
        NSData *data = [NSData dataWithBytes:definitions length:strlen(definitions)];
        freeCString((char *)definitions);
        id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if (![decoded isKindOfClass:NSArray.class]) return nil;
        self.engineParameterDefinitions = decoded;
        self.analysis = [[GyroflowAnalysis alloc] initWithPlugin:self];
        //---------------------------------------------------------
        // Write log file to disk when using NSLog:
        //---------------------------------------------------------
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *applicationSupportDirectory = [paths firstObject];
        NSString* logPath = [applicationSupportDirectory stringByAppendingString:@"/FxPlug.log"];
        
        freopen([logPath fileSystemRepresentation],"a+",stderr);
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        
        NSLog(@"[Gyroflow Toolbox Renderer] --------------------------------- START OF NEW SESSION ---------------------------------");
        NSLog(@"[Gyroflow Toolbox Renderer] Version: %@ (%@)", version, build);
        NSLog(@"[Gyroflow Toolbox Renderer] applicationSupportDirectory: '%@'", applicationSupportDirectory);

        //---------------------------------------------------------
        // Setup Grant Sandbox Access Array:
        //---------------------------------------------------------
        self.grantSandboxAccessURLs = [NSMutableArray array];

        //---------------------------------------------------------
        // Pre-load error messages:
        //---------------------------------------------------------
        self.cachedErrorImages = [NSMutableDictionary dictionary];
        for (NSString *errorID in @[ @"NoGyroflowProjectLoaded",
                                     @"GyroflowCoreRenderError" ]) {
            id cgObj = [self errorCGImageObjectForID:errorID];
            if (cgObj) {
                self.cachedErrorImages[errorID] = cgObj;
            } else {
                NSLog(@"[Gyroflow Toolbox Renderer] WARNING: couldn’t preload error image '%@'", errorID);
            }
        }

        //---------------------------------------------------------
        // Start the Gyroflow Core Logger:
        //---------------------------------------------------------
        NSString* gyroflowCoreLogPath = [applicationSupportDirectory stringByAppendingString:@"/GyroflowCore.log"];
        
        NSLog(@"[Gyroflow Toolbox Renderer] gyroflowCoreLogPath: '%@'", gyroflowCoreLogPath);
        
        startLogger([gyroflowCoreLogPath UTF8String]);
        
        //---------------------------------------------------------
        // Get the Lens Profiles path:
        //---------------------------------------------------------
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *lensProfilesPath = [mainBundle pathForResource:@"Lens Profiles" ofType:nil inDirectory:nil];
        
        //---------------------------------------------------------
        // Build cache of all the Lens Profile Names:
        //---------------------------------------------------------
        self.lensProfilesLookup = [self newLensProfileIdentifiersFromDirectory:lensProfilesPath];

        //NSLog(@"[Gyroflow Toolbox Renderer] lensProfilesLookup: %@", lensProfilesLookup);
        
        //---------------------------------------------------------
        // Cache the API Manager:
        //---------------------------------------------------------
        self.apiManager = newApiManager;

        //---------------------------------------------------------
        // Restore any previous global bookmarks:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
        NSArray *globalBookmarks = [userDefaults objectForKey:@"globalBookmarks"];
        if (globalBookmarks != nil) {
            for (NSData* data in globalBookmarks) {
                BOOL staleBookmark;
                NSError *bookmarkError = nil;
                NSURL* url = [NSURL URLByResolvingBookmarkData:data
                                                       options:NSURLBookmarkResolutionWithSecurityScope
                                                 relativeToURL:nil
                                           bookmarkDataIsStale:&staleBookmark
                                                         error:&bookmarkError];
                if (bookmarkError != nil) {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR: Failed to restore global bookmark due to: %@", bookmarkError.localizedDescription);
                    continue;
                }
                if (url == nil ) {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR: Failed to restore global bookmark.");
                    continue;
                }
                
                if (![url startAccessingSecurityScopedResource]) {
                    NSLog(@"[Gyroflow Toolbox Renderer] ERROR: Failed to start accessing global bookmark.");
                } else {
                    NSLog(@"[Gyroflow Toolbox Renderer] Successfully loaded global bookmark: %@", [url path]);
                    [_grantSandboxAccessURLs addObject:url];
                }
            }
        }
    }
    return self;
}

//---------------------------------------------------------
// Deallocates the memory occupied by the receiver:
//---------------------------------------------------------
- (void)dealloc {
    //---------------------------------------------------------
    // Stop accessing security scoped bookmarks:
    //---------------------------------------------------------
    if (_grantSandboxAccessURLs) {
        for (id url in _grantSandboxAccessURLs) {
            NSLog(@"[Gyroflow Toolbox Renderer] Stopping access to: %@", [url path]);
            [url stopAccessingSecurityScopedResource];
        }
    }

    //NSLog(@"[Gyroflow Toolbox Renderer] Successfully deallocated!");
}

//---------------------------------------------------------
// properties
//
// This method should return an NSDictionary defining the
// properties of the effect.
//---------------------------------------------------------
- (BOOL)properties:(NSDictionary * _Nonnull *)properties
             error:(NSError * _Nullable *)error
{
    *properties = @{
        //---------------------------------------------------------
        // Deprecated, and no longer required in FxPlug 4:
        //
        // * kFxPropertyKey_IsThreadSafe
        // * kFxPropertyKey_MayRemapTime
        // * kFxPropertyKey_PixelIndependent
        // * kFxPropertyKey_PreservesAlpha
        // * kFxPropertyKey_UsesLumaChroma
        // * kFxPropertyKey_UsesNonmatchingTextureLayout
        // * kFxPropertyKey_UsesRationalTime
        //---------------------------------------------------------
        kFxPropertyKey_MayRemapTime : @NO,
        
        //---------------------------------------------------------
        // @const      kFxPropertyKey_NeedsFullBuffer
        // @abstract   A key that determines whether the plug-in needs the entire image to do its
        //             processing, and can't tile its rendering.
        // @discussion This value of this key is a Boolean NSNumber indicating whether this plug-in
        //             needs the entire image to do its processing. Note that setting this value to
        //             YES incurs a significant performance penalty and makes your plug-in
        //             unable to render large input images. The default value is NO.
        //---------------------------------------------------------
        kFxPropertyKey_NeedsFullBuffer : [NSNumber numberWithBool:YES],
        
        //---------------------------------------------------------
        // @const      kFxPropertyKey_VariesWhenParamsAreStatic
        // @abstract   A key that determines whether your rendering varies even when
        //             the parameters remain the same.
        // @discussion The value for this key is a Boolean NSNumber indicating whether this effect
        //             changes its rendering even when the parameters don't change. This can happen if
        //             your rendering is based on timing in addition to parameters, for example. Note that
        //             this property is only checked once when the filter is applied, so it
        //             should go in static properties rather than dynamic properties.
        //---------------------------------------------------------
        kFxPropertyKey_VariesWhenParamsAreStatic : [NSNumber numberWithBool:YES],
        
        //---------------------------------------------------------
        // @const      kFxPropertyKey_ChangesOutputSize
        // @abstract   A key that determines whether your filter has the ability to change the size
        //             of its output to be different than the size of its input.
        // @discussion The value of this key is a Boolean NSNumber indicating whether your filter
        //             returns an output that has a different size than the input. If not, return "NO"
        //             and your filter's @c -destinationImageRect:sourceImages:pluginState:atTime:error:
        //             method will not be called.
        //---------------------------------------------------------
        kFxPropertyKey_ChangesOutputSize : [NSNumber numberWithBool:YES],
        
        //---------------------------------------------------------
        // @const      kFxPropertyKey_DesiredProcessingColorInfo
        // @abstract   Key for properties dictionary
        // @discussion The value for this key is an NSNumber indicating the colorspace
        //             that the plug-in would like to process in. This color space is
        //             expressed as an FxImageColorInfo enum. If a plug-in specifies this,
        //             and the host supports it, all inputs will be in this colorspace,
        //             and the output must also be in this colorspace. This may not
        //             be supported by all hosts, so the plug-in should still check
        //             the colorInfo of its input and output images.
        //---------------------------------------------------------
        kFxPropertyKey_DesiredProcessingColorInfo : [NSNumber numberWithInt:kFxImageColorInfo_RGB_GAMMA_VIDEO],
    };
    return YES;
}

//---------------------------------------------------------
// createViewForParameterID
//
// Provides an NSView to be associated with the given
// parameter.
//---------------------------------------------------------
- (NSView*)createViewForParameterID:(UInt32)parameterID
{
    for (NSDictionary *definition in self.engineParameterDefinitions) {
        if ([definition[@"id"] unsignedIntValue] == parameterID && definition[@"button_title"]) {
            return [[CustomButtonView alloc] initWithParentPlugin:self buttonID:parameterID buttonTitle:definition[@"button_title"]];
        }
    }
    if (parameterID == kCB_ImportGyroflowProject) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_ImportGyroflowProject
                                                  buttonTitle:@"Import Gyroflow Project"];
    } else if (parameterID == kCB_ImportMediaFile) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_ImportMediaFile
                                                  buttonTitle:@"Import Media File"];
    } else if (parameterID == kCB_ReloadGyroflowProject) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_ReloadGyroflowProject
                                                  buttonTitle:@"Reload Gyroflow Project"];
    } else if (parameterID == kCB_ExportGyroflowProject) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_ExportGyroflowProject
                                                  buttonTitle:@"Export Gyroflow Project"];
    } else if (parameterID == kCB_LaunchGyroflow) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_LaunchGyroflow
                                                  buttonTitle:@"Launch Gyroflow"];
    } else if (parameterID == kCB_LoadLastGyroflowProject) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_LoadLastGyroflowProject
                                                  buttonTitle:@"Import Last Gyroflow Project"];
    } else if (parameterID == kCB_DropZone) {
        return [[CustomDropZoneView alloc] initWithParentPlugin:self
                                                       buttonID:kCB_DropZone
                                                    buttonTitle:@"Import Dropped Clip"];
    } else if (parameterID == kCB_RevealInFinder) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_RevealInFinder
                                                  buttonTitle:@"Reveal in Finder"];
    } else if (parameterID == kCB_LoadPresetLensProfile) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_LoadPresetLensProfile
                                                  buttonTitle:@"Load Preset/Lens Profile"];
    } else if (parameterID == kCB_Header) {
        NSRect frameRect = NSMakeRect(0, 0, 200, 324); // x y w h
        return  [[HeaderView alloc] initWithFrame:frameRect];
    } else if (parameterID == kCB_OpenUserGuide) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_OpenUserGuide
                                                  buttonTitle:@"Open User Guide"];
    } else if (parameterID == kCB_Settings) {
        return [[CustomButtonView alloc] initWithParentPlugin:self
                                                     buttonID:kCB_Settings
                                                  buttonTitle:@"Settings"];
    } else {
        NSLog(@"[Gyroflow Toolbox Renderer] BUG - createViewForParameterID requested a parameterID that we haven't allowed for: %u", (unsigned int)parameterID);
        return nil;
    }
}

//---------------------------------------------------------
//
#pragma mark - Parameters
//
//---------------------------------------------------------

//---------------------------------------------------------
// addParametersWithError
//
// This method is where a plug-in defines its list of parameters.
//---------------------------------------------------------
/// Creates the complete inspector from the Rust catalog, preserving the saved FxPlug identifiers.
- (BOOL)addParametersWithError:(NSError **)error {
    id<FxParameterCreationAPI_v5> api = [self.apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if (!api) {
        if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_APIUnavailable
            userInfo:@{NSLocalizedDescriptionKey: @"The FxPlug parameter API is unavailable."}];
        return NO;
    }
    for (NSDictionary *definition in self.engineParameterDefinitions) {
        UInt32 identifier = [definition[@"id"] unsignedIntValue];
        NSString *kind = definition[@"kind"];
        NSString *name = definition[@"name"];
        UInt32 flags = kFxParameterFlag_DEFAULT;
        if (![definition[@"animated"] boolValue]) flags |= kFxParameterFlag_NOT_ANIMATABLE;
        if ([definition[@"hidden"] boolValue]) flags |= kFxParameterFlag_HIDDEN;
        if ([definition[@"disabled"] boolValue]) flags |= kFxParameterFlag_DISABLED;
        BOOL added = NO;
        if ([kind isEqualToString:@"slider"]) {
            added = [api addFloatSliderWithName:name parameterID:identifier defaultValue:[definition[@"default"] doubleValue]
                parameterMin:[definition[@"min"] doubleValue] parameterMax:[definition[@"max"] doubleValue]
                sliderMin:[definition[@"min"] doubleValue] sliderMax:[definition[@"max"] doubleValue]
                delta:[definition[@"delta"] doubleValue] parameterFlags:flags];
        } else if ([kind isEqualToString:@"toggle"]) {
            added = [api addToggleButtonWithName:name parameterID:identifier defaultValue:[definition[@"default"] boolValue] parameterFlags:flags];
        } else if ([kind isEqualToString:@"menu"]) {
            added = [api addPopupMenuWithName:name parameterID:identifier defaultValue:[definition[@"default"] unsignedIntValue]
                menuEntries:definition[@"entries"] parameterFlags:flags];
        } else if ([kind isEqualToString:@"text"]) {
            added = [api addStringParameterWithName:name parameterID:identifier defaultValue:definition[@"default"] parameterFlags:flags];
        } else if ([kind isEqualToString:@"custom"]) {
            added = [api addCustomParameterWithName:name parameterID:identifier defaultValue:definition[@"default"]
                parameterFlags:flags | kFxParameterFlag_CUSTOM_UI];
        } else if ([kind isEqualToString:@"group"]) {
            added = [api startParameterSubGroup:name parameterID:identifier
                parameterFlags:kFxParameterFlag_DEFAULT | ([definition[@"collapsed"] boolValue] ? kFxParameterFlag_COLLAPSED : 0)];
        } else if ([kind isEqualToString:@"end-group"]) {
            added = [api endParameterSubGroup];
        }
        if (!added) {
            if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
                userInfo:@{NSLocalizedDescriptionKey: @"Unable to create a Gyroflow inspector control."}];
            return NO;
        }
    }
    return YES;
}

/// Reads native values without interpreting units, ranges, or stabilization policy.
- (NSDictionary<NSString *, NSNumber *> *)parameterValuesAtTime:(CMTime)time
    parameterAPI:(id<FxParameterRetrievalAPI_v6>)api error:(NSError **)error {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSDictionary *definition in self.engineParameterDefinitions) {
        UInt32 identifier = [definition[@"id"] unsignedIntValue];
        NSString *kind = definition[@"kind"];
        NSNumber *value = nil;
        if ([kind isEqualToString:@"slider"]) {
            double number = 0;
            if ([api getFloatValue:&number fromParameter:identifier atTime:time]) value = @(number);
        } else if ([kind isEqualToString:@"toggle"]) {
            BOOL flag = NO;
            if ([api getBoolValue:&flag fromParameter:identifier atTime:time]) value = @(flag);
        } else if ([kind isEqualToString:@"menu"]) {
            int index = 0;
            if ([api getIntValue:&index fromParameter:identifier atTime:time]) value = @(index);
        } else { continue; }
        if (!value) {
            if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
                userInfo:@{NSLocalizedDescriptionKey: @"Unable to read a Gyroflow inspector value."}];
            return nil;
        }
        values[[@(identifier) stringValue]] = value;
    }
    return values;
}

//---------------------------------------------------------
// parameterChanged:atTime:error:
//
// Executes when the host detects that a parameter has changed.
//---------------------------------------------------------
- (BOOL)parameterChanged:(UInt32)paramID
                  atTime:(CMTime)time
                   error:(NSError * _Nullable *)error
{
    // Rust keys the cache by project, curve snapshot, and stretch settings.
    return YES;
}

/// Transfers curve identity to Rust, which samples only changed curves and owns interpolation.
- (NSString *)hostKeyframesForProject:(NSString *)project
                       parameterAPI:(id<FxParameterRetrievalAPI_v6>)parameterAPI
                          timingAPI:(id<FxTimingAPI_v4>)timingAPI
                     timelineOrigin:(CMTime)timelineOrigin
                          frameRate:(double)frameRate
                              error:(NSError **)error
{
    id<FxKeyframeAPI_v3> keyframeAPI = [self.apiManager apiForProtocol:@protocol(FxKeyframeAPI_v3)];
    if (!keyframeAPI || project.length == 0) return nil;
    const char *identifiersString = getKeyframeParameterIDs();
    NSData *identifiersData = [NSData dataWithBytes:identifiersString length:strlen(identifiersString)];
    freeCString((char *)identifiersString);
    NSArray<NSNumber *> *identifiers = [NSJSONSerialization JSONObjectWithData:identifiersData options:0 error:error];
    if (![identifiers isKindOfClass:NSArray.class]) return nil;
    GyroflowParameterReader reader = { parameterAPI, timingAPI, timelineOrigin };
    NSMutableArray *parameters = [NSMutableArray arrayWithCapacity:identifiers.count];
    for (NSNumber *identifier in identifiers) {
        NSUInteger count = 0;
        NSError *keyframeError = [keyframeAPI keyframeCount:&count forParameter:identifier.unsignedIntValue andChannel:0];
        if (keyframeError) { if (error) *error = keyframeError; return nil; }
        double initialValue = 0.0;
        if (!readGyroflowHostParameter(&reader, identifier.unsignedIntValue, 0, &initialValue)) {
            if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
                userInfo:@{NSLocalizedDescriptionKey: @"Unable to read an animation parameter from Final Cut Pro."}];
            return nil;
        }
        NSMutableArray *keys = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger index = 0; index < count; index++) {
            FxKeyframe keyframe;
            FxInitKeyframe(keyframe, kFxKeyframe_CurrentVersion);
            keyframeError = [keyframeAPI keyframe:&keyframe forParameter:identifier.unsignedIntValue channel:0 andIndex:index];
            if (keyframeError) { if (error) *error = keyframeError; return nil; }
            CMTime timelineTime = kCMTimeInvalid;
            [timingAPI timelineTime:&timelineTime fromInputTime:keyframe.time];
            CMTime relativeTime = CMTimeConvertScale(CMTimeSubtract(timelineTime, timelineOrigin), 1000000, kCMTimeRoundingMethod_RoundHalfAwayFromZero);
            double value = 0.0;
            if (!CMTIME_IS_NUMERIC(relativeTime) || ![parameterAPI getFloatValue:&value fromParameter:identifier.unsignedIntValue atTime:keyframe.time]) {
                if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidTime
                    userInfo:@{NSLocalizedDescriptionKey: @"Unable to read a keyframe time or value from Final Cut Pro."}];
                return nil;
            }
            NSData *shape = [NSData dataWithBytes:&keyframe length:sizeof(keyframe)];
            [keys addObject:@{@"time_us": @(relativeTime.value), @"value": @(value), @"shape": [shape base64EncodedStringWithOptions:0]}];
        }
        [parameters addObject:@{@"id": identifier, @"value": @(initialValue), @"keys": keys}];
    }
    CMTime duration = kCMTimeInvalid;
    [timingAPI durationTimeOfInputToFilter:&duration];
    double inputRotation = 0.0;
    if (!readGyroflowHostParameter(&reader, kCB_InputRotation, 0, &inputRotation)) {
        if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
            userInfo:@{NSLocalizedDescriptionKey: @"Unable to read the input rotation from Final Cut Pro."}];
        return nil;
    }
    CMTime initialTime = kCMTimeInvalid;
    [timingAPI inputTime:&initialTime fromTimelineTime:timelineOrigin];
    NSDictionary *controls = [self parameterValuesAtTime:initialTime parameterAPI:parameterAPI error:error];
    if (!controls) return nil;
    NSDictionary *signature = @{@"fps": @(frameRate), @"parameters": parameters,
        @"input_rotation": @(inputRotation),
        @"controls": controls,
        @"origin_value": @(timelineOrigin.value), @"origin_scale": @(timelineOrigin.timescale),
        @"duration_value": @(duration.value), @"duration_scale": @(duration.timescale)};
    NSData *signatureData = [NSJSONSerialization dataWithJSONObject:signature options:NSJSONWritingSortedKeys error:error];
    if (!signatureData) return nil;
    NSString *signatureString = [[NSString alloc] initWithData:signatureData encoding:NSUTF8StringEncoding];
    const char *snapshot = buildHostKeyframes(project.UTF8String, signatureString.UTF8String, &reader, readGyroflowHostParameter);
    NSString *result = [NSString stringWithUTF8String:snapshot];
    freeCString((char *)snapshot);
    if ([result isEqualToString:@"FAIL"]) {
        if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
            userInfo:@{NSLocalizedDescriptionKey: @"Gyroflow could not read the animation curves from Final Cut Pro."}];
        return nil;
    }
    return result;
}

/// Populates host controls from Rust without parsing Gyroflow documents in Objective-C.
- (void)applyProjectDefaultsFromProject:(NSString *)project
                          parameterAPI:(id<FxParameterSettingAPI_v5>)parameterAPI
{
    const char *defaultsString = getEngineControlDefaults(project.UTF8String);
    NSData *defaultsData = [NSData dataWithBytes:defaultsString length:strlen(defaultsString)];
    freeCString((char *)defaultsString);
    NSDictionary *values = [NSJSONSerialization JSONObjectWithData:defaultsData options:0 error:NULL];
    if (![values isKindOfClass:NSDictionary.class]) return;
    [self applyToolboxControlValues:values parameterAPI:parameterAPI];
}

- (void)applyToolboxControlValues:(NSDictionary<NSString *, NSNumber *> *)values {
    id<FxParameterSettingAPI_v5> parameterAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    [self applyToolboxControlValues:values parameterAPI:parameterAPI];
}

- (void)applyToolboxControlValues:(NSDictionary<NSString *, NSNumber *> *)values parameterAPI:(id<FxParameterSettingAPI_v5>)parameterAPI {
    for (NSDictionary *definition in self.engineParameterDefinitions) {
        UInt32 identifier = [definition[@"id"] unsignedIntValue];
        NSNumber *value = values[[@(identifier) stringValue]];
        if (!value) continue;
        NSString *kind = definition[@"kind"];
        if ([kind isEqualToString:@"slider"]) {
            [parameterAPI setFloatValue:value.doubleValue toParameter:identifier atTime:kCMTimeZero];
        } else if ([kind isEqualToString:@"toggle"]) {
            [parameterAPI setBoolValue:value.boolValue toParameter:identifier atTime:kCMTimeZero];
        } else if ([kind isEqualToString:@"menu"]) {
            [parameterAPI setIntValue:value.intValue toParameter:identifier atTime:kCMTimeZero];
        }
    }
}

//---------------------------------------------------------
//
#pragma mark - Pre-Render
//
//---------------------------------------------------------

//---------------------------------------------------------
// pluginState:atTime:quality:error
//
// Your plug-in should get its parameter values, do any calculations it needs to
// from those values, and package up the result to be used later with rendering.
// The host application will call this method before rendering. The
// FxParameterRetrievalAPI* is valid during this call. Use it to get the values of
// your plug-in's parameters, then put those values or the results of any calculations
// you need to do with those parameters to render into an NSData that you return
// to the host application. The host will pass it back to you during subsequent calls.
// Do not re-use the NSData; always create a new one as this method may be called
// on multiple threads at the same time.
//---------------------------------------------------------
- (BOOL)pluginState:(NSData**)pluginState
             atTime:(CMTime)renderTime
            quality:(FxQuality)qualityLevel
              error:(NSError**)error
{

    BOOL succeeded = NO;

    //---------------------------------------------------------
    // Load the timing API:
    //---------------------------------------------------------
    id<FxTimingAPI_v4> timingAPI = [self.apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
    if (timingAPI == nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve FxTimingAPI_v4 in pluginStateAtTime.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_FailedToLoadTimingAPI
                                     userInfo:@{
                NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }

    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve FxParameterRetrievalAPI_v6 in pluginStateAtTime.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_FailedToLoadParameterGetAPI
                                     userInfo:@{
                NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }

    //---------------------------------------------------------
    // Create a new Parameters "holder":
    //---------------------------------------------------------
    GyroflowParameters *params = [[GyroflowParameters alloc] init];

    //---------------------------------------------------------
    // Get the frame to render:
    //---------------------------------------------------------
    CMTime timelineFrameDuration = kCMTimeZero;
    timelineFrameDuration = CMTimeMake( [timingAPI timelineFpsDenominatorForEffect:self],
                                       (int)[timingAPI timelineFpsNumeratorForEffect:self] );

    CMTime timelineTime = kCMTimeZero;
    [timingAPI timelineTime:&timelineTime fromInputTime:renderTime];

    CMTime startTimeOfInputToFilter = kCMTimeZero;
    [timingAPI startTimeForEffect:&startTimeOfInputToFilter];

    CMTime startTimeOfInputToFilterInTimelineTime = kCMTimeZero;
    [timingAPI timelineTime:&startTimeOfInputToFilterInTimelineTime fromInputTime:startTimeOfInputToFilter];

    Float64 timelineTimeMinusStartTimeOfInputToFilterNumerator = (Float64)timelineTime.value * (Float64)startTimeOfInputToFilterInTimelineTime.timescale - (Float64)startTimeOfInputToFilterInTimelineTime.value * (Float64)timelineTime.timescale;
    Float64 timelineTimeMinusStartTimeOfInputToFilterDenominator = (Float64)timelineTime.timescale * (Float64)startTimeOfInputToFilterInTimelineTime.timescale;

    Float64 frame = ( ((Float64)timelineTimeMinusStartTimeOfInputToFilterNumerator / (Float64)timelineTimeMinusStartTimeOfInputToFilterDenominator) / ((Float64)timelineFrameDuration.value / (Float64)timelineFrameDuration.timescale) );

    //---------------------------------------------------------
    // Calculate the Timestamp:
    //---------------------------------------------------------
    Float64 timelineFpsNumerator    = [timingAPI timelineFpsNumeratorForEffect:self];
    Float64 timelineFpsDenominator  = [timingAPI timelineFpsDenominatorForEffect:self];
    Float64 frameRate               = timelineFpsNumerator / timelineFpsDenominator;
    Float64 timestamp               = (frame / frameRate) * 1000000.0;
    params.timestamp                = @(llround(timestamp));

    /*
     NSLog(@"---------------------------------");
     NSLog(@"timelineFrameDuration: %.2f seconds", CMTimeGetSeconds(timelineFrameDuration));
     NSLog(@"timelineTime: %.2f seconds", CMTimeGetSeconds(timelineTime));
     NSLog(@"startTimeOfInputToFilter: %.2f seconds", CMTimeGetSeconds(startTimeOfInputToFilter));
     NSLog(@"startTimeOfInputToFilterInTimelineTime: %.2f seconds", CMTimeGetSeconds(startTimeOfInputToFilterInTimelineTime));
     NSLog(@"timelineTimeMinusStartTimeOfInputToFilterNumerator: %f", timelineTimeMinusStartTimeOfInputToFilterNumerator);
     NSLog(@"timelineTimeMinusStartTimeOfInputToFilterDenominator: %f", timelineTimeMinusStartTimeOfInputToFilterDenominator);
     NSLog(@"frame: %f", frame);
     NSLog(@"timelineFpsNumerator: %f", timelineFpsNumerator);
     NSLog(@"timelineFpsDenominator: %f", timelineFpsDenominator);
     NSLog(@"frameRate: %f", frameRate);
     NSLog(@"timestamp: %f", timestamp);
     NSLog(@"---------------------------------");
     */

    //---------------------------------------------------------
    // Unique Identifier:
    //---------------------------------------------------------
    NSString *uniqueIdentifier;
    [paramGetAPI getStringParameterValue:&uniqueIdentifier fromParameter:kCB_UniqueIdentifier];
    params.uniqueIdentifier = uniqueIdentifier;

    //NSLog(@"[Gyroflow Toolbox Renderer] Unique Identifier in Plugin State: %@", uniqueIdentifier);

    //---------------------------------------------------------
    // Gyroflow Path:
    //---------------------------------------------------------
    NSString *gyroflowPath;
    [paramGetAPI getStringParameterValue:&gyroflowPath fromParameter:kCB_GyroflowProjectPath];
    params.gyroflowPath = gyroflowPath;

    //---------------------------------------------------------
    // Gyroflow Data:
    //---------------------------------------------------------
    NSString *gyroflowData;
    [paramGetAPI getStringParameterValue:&gyroflowData fromParameter:kCB_GyroflowProjectData];

    //---------------------------------------------------------
    // If the Gyroflow Project data is base64 encoded, try
    // to decode it first, otherwise pass the original string:
    //---------------------------------------------------------
    params.gyroflowData = gyroflowData;
    NSData *base64EncodedData = [[NSData alloc] initWithBase64EncodedString:gyroflowData ?: @"" options:0];
    if (base64EncodedData != nil) {
        NSString *decodedGyroflowData = [[NSString alloc] initWithData:base64EncodedData encoding:NSUTF8StringEncoding];
        if (decodedGyroflowData != nil) {
            params.gyroflowData = decodedGyroflowData;
        }
    } else {
        params.gyroflowData = gyroflowData;
    }

    NSDictionary *values = [self parameterValuesAtTime:renderTime parameterAPI:paramGetAPI error:error];
    if (!values) return NO;
    NSData *valuesData = [NSJSONSerialization dataWithJSONObject:values options:NSJSONWritingSortedKeys error:error];
    if (!valuesData) return NO;
    params.parameterValues = [[NSString alloc] initWithData:valuesData encoding:NSUTF8StringEncoding];
    for (NSDictionary *definition in self.engineParameterDefinitions) {
        NSString *archiveKey = definition[@"archive"];
        if (archiveKey) [params setValue:values[[definition[@"id"] stringValue]] forKey:archiveKey];
    }
    GyroflowRenderOptions renderOptions;
    if (!getOptionsFromParameters(params.parameterValues.UTF8String, &renderOptions)) {
        if (error) *error = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
            userInfo:@{NSLocalizedDescriptionKey: @"The stabilisation settings are invalid."}];
        return NO;
    }
    params.renderOptions = [NSData dataWithBytes:&renderOptions length:sizeof(renderOptions)];
    NSError *animationError = nil;
    params.hostKeyframes = [self hostKeyframesForProject:params.gyroflowData
        parameterAPI:paramGetAPI timingAPI:timingAPI
        timelineOrigin:startTimeOfInputToFilterInTimelineTime frameRate:frameRate error:&animationError];
    if (animationError) { if (error) *error = animationError; return NO; }

    //---------------------------------------------------------
    // Write the parameters to the pluginState as `NSData`:
    //---------------------------------------------------------
    NSError *newPluginStateError;
    NSData *newPluginState = [NSKeyedArchiver archivedDataWithRootObject:params requiringSecureCoding:YES error:&newPluginStateError];
    if (newPluginState == nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString* errorMessage = [NSString stringWithFormat:@"ERROR - Failed to create newPluginState due to '%@'", [newPluginStateError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_FailedToCreatePluginState
                                     userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }

    *pluginState = newPluginState;

    if (*pluginState != nil) {
        succeeded = YES;
    } else {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString* errorMessage = @"ERROR - pluginState is nil in pluginState method.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        *error = [NSError errorWithDomain:FxPlugErrorDomain
                                     code:kFxError_PlugInStateIsNil
                                 userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        succeeded = NO;
    }

    return succeeded;
}

//---------------------------------------------------------
//
#pragma mark - Render
//
//---------------------------------------------------------

//---------------------------------------------------------
// destinationImageRect:sourceImages:destinationImage:pluginState:atTime:error
//
// This method will calculate the rectangular bounds of the output
// image given the various inputs and plug-in state
// at the given render time.
// It will pass in an array of images, the plug-in state
// returned from your plug-in's -pluginStateAtTime:error: method,
// and the render time.
//---------------------------------------------------------
- (BOOL)destinationImageRect:(FxRect *)destinationImageRect
                sourceImages:(NSArray<FxImageTile *> *)sourceImages
            destinationImage:(nonnull FxImageTile *)destinationImage
                 pluginState:(NSData *)pluginState
                      atTime:(CMTime)renderTime
                       error:(NSError * _Nullable *)outError
{
    //---------------------------------------------------------
    // Make sure there is actually a source image:
    //---------------------------------------------------------
    if (sourceImages.count < 1) {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_ThirdPartyDeveloperStart + 5
                                        userInfo:@{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] FATAL ERROR - No sourceImages in -destinationImageRect."}];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // The output rect is the same as the input rect:
    //---------------------------------------------------------
    *destinationImageRect = sourceImages [ 0 ].imagePixelBounds;
    
    return YES;
}

//---------------------------------------------------------
// sourceTileRect:sourceImageIndex:sourceImages:destinationTileRect:destinationImage:pluginState:atTime:error
//
// Calculate tile of the source image we need
// to render the given output tile.
//---------------------------------------------------------
- (BOOL)sourceTileRect:(FxRect *)sourceTileRect
      sourceImageIndex:(NSUInteger)sourceImageIndex
          sourceImages:(NSArray<FxImageTile *> *)sourceImages
   destinationTileRect:(FxRect)destinationTileRect
      destinationImage:(FxImageTile *)destinationImage
           pluginState:(NSData *)pluginState
                atTime:(CMTime)renderTime
                 error:(NSError * _Nullable *)outError
{
    //---------------------------------------------------------
    // The input tile will be the same size as the output tile:
    //---------------------------------------------------------
    *sourceTileRect = destinationTileRect;
    
    return YES;
}

//---------------------------------------------------------
// Render an Error Message:
//---------------------------------------------------------
- (BOOL)renderErrorMessageWithID:(NSString*)errorMessageID
                destinationImage:(FxImageTile * _Nonnull)destinationImage
                      fullHeight:(float)fullHeight
                       fullWidth:(float)fullWidth
                        outError:(NSError * _Nullable * _Nullable)outError
                    outputHeight:(float)outputHeight
                     outputWidth:(float)outputWidth
                    sourceImages:(NSArray<FxImageTile *> * _Nonnull)sourceImages
{
    //---------------------------------------------------------
    // Get CGImage from NSImage:
    //---------------------------------------------------------
    CGImageRef cgImage = (__bridge CGImageRef)self.cachedErrorImages[errorMessageID];
    if (!cgImage) {
        //---------------------------------------------------------
        // Fail with error message:
        //---------------------------------------------------------
        NSString *errorMessage = [NSString stringWithFormat:@"FATAL ERROR: Unable to get CGImage from cache: %@", errorMessageID];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_AssetLoadFailed
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }

    // ---------------------------------------------------------
    // Flip image vertically to correct coordinate system:
    // ---------------------------------------------------------
    CGSize imgSize = CGSizeMake(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    CGBitmapInfo info = kCGBitmapByteOrder32Host | (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    CGContextRef flipCtx = CGBitmapContextCreate(NULL,
                                                 imgSize.width,
                                                 imgSize.height,
                                                 8,
                                                 0,
                                                 CGImageGetColorSpace(cgImage),
                                                 info);
    CGContextTranslateCTM(flipCtx, 0, imgSize.height);
    CGContextScaleCTM(flipCtx, 1.0, -1.0);
    CGContextDrawImage(flipCtx, CGRectMake(0, 0, imgSize.width, imgSize.height), cgImage);
    CGImageRef flipped = CGBitmapContextCreateImage(flipCtx);
    CGContextRelease(flipCtx);

    // NOTE: we don't need to release `cgImage` here.

    CIImage *errorCI = [CIImage imageWithCGImage:flipped];
    CGImageRelease(flipped);
    if (!errorCI) {
        //---------------------------------------------------------
        // Fail with error message:
        //---------------------------------------------------------
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to create CIImage."];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_ImageCreationFailed
                                        userInfo:@{NSLocalizedDescriptionKey:errorMessage}];
        }
        return NO;
    }

    // ---------------------------------------------------------
    // Compute square-pixel canvas via inversePixelTransform:
    // ---------------------------------------------------------
    FxRect imgBounds = destinationImage.imagePixelBounds;
    FxMatrix44 *invTrans = [destinationImage inversePixelTransform];
    FxPoint2D ll = { imgBounds.left, imgBounds.bottom };
    FxPoint2D ur = { imgBounds.right, imgBounds.top };
    FxPoint2D llSq = [invTrans transform2DPoint:ll];
    FxPoint2D urSq = [invTrans transform2DPoint:ur];
    CGFloat squareW = urSq.x - llSq.x;
    CGFloat squareH = urSq.y - llSq.y;

    // ---------------------------------------------------------
    // Fit width, maintain aspect, center vertically:
    // ---------------------------------------------------------
    CGFloat imgW = errorCI.extent.size.width;
    CGFloat scale = squareW / imgW;
    CGFloat fittedH = errorCI.extent.size.height * scale;
    CGFloat yOff = (squareH - fittedH) * 0.5;
    CGAffineTransform fitXform = CGAffineTransformMakeScale(scale, scale);
    CGAffineTransform centXform = CGAffineTransformMakeTranslation(0, yOff);
    CIImage *fitted = [errorCI imageByApplyingTransform:CGAffineTransformConcat(fitXform, centXform)];

    // ---------------------------------------------------------
    // Fill the entire square-pixel canvas with white:
    // ---------------------------------------------------------
    CIImage *whiteBg = [[CIImage imageWithColor:
                         [CIColor colorWithRed:1 green:1 blue:1 alpha:1]]
                        imageByCroppingToRect:
                            CGRectMake(0, 0, squareW, squareH)];
    CIImage *comp = [fitted imageByCompositingOverImage:whiteBg];

    // ---------------------------------------------------------
    // Map back to device pixels with forward transform:
    // ---------------------------------------------------------
    FxMatrix44 *fwdTrans = [destinationImage pixelTransform];
    FxPoint2D dev00 = [fwdTrans transform2DPoint:(FxPoint2D){0,0}];
    FxPoint2D dev10 = [fwdTrans transform2DPoint:(FxPoint2D){1,0}];
    FxPoint2D dev01 = [fwdTrans transform2DPoint:(FxPoint2D){0,1}];
    CGAffineTransform toDevice = CGAffineTransformMake(dev10.x - dev00.x,
                                                       dev10.y - dev00.y,
                                                       dev01.x - dev00.x,
                                                       dev01.y - dev00.y,
                                                       dev00.x,
                                                       dev00.y);
    CIImage *finalImage = [comp imageByApplyingTransform:toDevice];

    // ---------------------------------------------------------
    // Render via Metal-backed CIContext:
    // ---------------------------------------------------------
    IOSurfaceRef surf = (__bridge IOSurfaceRef)destinationImage.ioSurface;
    id<MTLDevice> device = [[MetalDeviceCache deviceCache] deviceWithRegistryID:destinationImage.deviceRegistryID];
    CIContext *ciCtx = [CIContext contextWithMTLDevice:device];
    CIRenderDestination *dest = [[CIRenderDestination alloc] initWithIOSurface:(__bridge IOSurface *)surf];
    dest.alphaMode = CIRenderDestinationAlphaUnpremultiplied;
    NSError *renderErr = nil;
    [ciCtx startTaskToRender:finalImage toDestination:dest error:&renderErr];
    if (renderErr) {
        //---------------------------------------------------------
        // Fail with error message:
        //---------------------------------------------------------
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to render due to: %@", renderErr.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_ImageCreationFailed
                                        userInfo:@{NSLocalizedDescriptionKey:errorMessage}];
        }
        return NO;
    }

    return YES;
}

//---------------------------------------------------------
// renderDestinationImage:sourceImages:pluginState:atTime:error:
//
// The host will call this method when it wants your plug-in to render an image
// tile of the output image. It will pass in each of the input tiles needed as well
// as the plug-in state needed for the calculations. Your plug-in should do all its
// rendering in this method. It should not attempt to use the FxParameterRetrievalAPI*
// object as it is invalid at this time. Note that this method will be called on
// multiple threads at the same time.
//---------------------------------------------------------
- (BOOL)renderDestinationImage:(FxImageTile *)destinationImage
                  sourceImages:(NSArray<FxImageTile *> *)sourceImages
                   pluginState:(NSData *)pluginState
                        atTime:(CMTime)renderTime
                         error:(NSError * _Nullable *)outError
{
    //---------------------------------------------------------
    // Make sure the plugin state is valid:
    //---------------------------------------------------------
    if (pluginState == nil) {
        NSString *errorMessage = @"FATAL ERROR: Invalid plugin state received from host - pluginState was nil.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    if (sourceImages.count == 0 || sourceImages[0].ioSurface == nil) {
        NSString *errorMessage = @"FATAL ERROR: Invalid plugin state received from host - sourceImages[0].ioSurface was nil.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    if (destinationImage.ioSurface == nil) {
        NSString *errorMessage = @"FATAL ERROR: Invalid plugin state received from host - destinationImage.ioSurface was nil.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Read the parameter parameter values and other info
    // about the source tile from the `pluginState`:
    //---------------------------------------------------------
    NSError *paramsError;
    GyroflowParameters *params = [NSKeyedUnarchiver unarchivedObjectOfClass:[GyroflowParameters class] fromData:pluginState error:&paramsError];
    if (params == nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"FATAL ERROR - Parameters was nil in -renderDestinationImage due to '%@'.", [paramsError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Get the parameter data:
    //---------------------------------------------------------
    NSString *uniqueIdentifier          = params.uniqueIdentifier;
    NSNumber *timestamp                 = params.timestamp;
    NSString *gyroflowPath              = params.gyroflowPath;
    NSString *gyroflowData              = params.gyroflowData;
    NSNumber *fov                       = params.fov;
    NSNumber *smoothness                = params.smoothness;
    NSNumber *lensCorrection            = params.lensCorrection;
    
    NSNumber *horizonLock               = params.horizonLock;
    NSNumber *horizonRoll               = params.horizonRoll;
    NSNumber *positionOffsetX           = params.positionOffsetX;
    NSNumber *positionOffsetY           = params.positionOffsetY;
    NSNumber *inputRotation             = params.inputRotation;
    NSNumber *videoRotation             = params.videoRotation;
    
    NSNumber *fovOverview               = params.fovOverview;
    NSNumber *disableGyroflowStretch    = params.disableGyroflowStretch;
    
    //---------------------------------------------------------
    // Calculate output width & height:
    //---------------------------------------------------------
    float outputWidth       = (destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left);
    float outputHeight      = (destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom);
    float fullWidth         = (destinationImage.imagePixelBounds.right - destinationImage.imagePixelBounds.left);
    float fullHeight        = (destinationImage.imagePixelBounds.top - destinationImage.imagePixelBounds.bottom);
    
    //---------------------------------------------------------
    // There's no unique identifier or Gyroflow Data,
    // so let's abort:
    //---------------------------------------------------------
    if (uniqueIdentifier == nil || [uniqueIdentifier isEqualToString:@""] || gyroflowData == nil || [gyroflowData isEqualToString:@""]) {
        return [self renderErrorMessageWithID:@"NoGyroflowProjectLoaded"
                             destinationImage:destinationImage
                                   fullHeight:fullHeight
                                    fullWidth:fullWidth
                                     outError:outError
                                 outputHeight:outputHeight
                                  outputWidth:outputWidth
                                 sourceImages:sourceImages];
    }
    
    //---------------------------------------------------------
    // Setup the Metal Device Cache:
    //---------------------------------------------------------
    MetalDeviceCache* deviceCache = [MetalDeviceCache deviceCache];

    //---------------------------------------------------------
    // Use the Destination Metal Device for Gyroflow
    // processing:
    //---------------------------------------------------------
    id<MTLDevice> metalDevice = [deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID];

    //---------------------------------------------------------
    // Setup our input texture:
    //
    // Retrieve a Metal texture from the IOSurface for
    // rendering on the passed-in device. The returned texture
    // is autoreleased
    //---------------------------------------------------------
    id<MTLTexture> inputTexture = [sourceImages[0] metalTextureForDevice:metalDevice];

    //---------------------------------------------------------
    // Setup our output texture:
    //
    // Retrieve a Metal texture from the IOSurface for
    // rendering on the passed-in device. The returned texture
    // is autoreleased
    //---------------------------------------------------------
    id<MTLTexture> outputTexture = [destinationImage metalTextureForDevice:metalDevice];

    if (!inputTexture || !outputTexture || inputTexture.width != outputTexture.width ||
        inputTexture.height != outputTexture.height || inputTexture.pixelFormat != outputTexture.pixelFormat) {
        if (outError) *outError = [NSError errorWithDomain:FxPlugErrorDomain code:kFxError_InvalidParameter
            userInfo:@{NSLocalizedDescriptionKey: @"The source and destination Metal textures must have matching dimensions and pixel formats."}];
        return NO;
    }

    //---------------------------------------------------------
    // Determine the Pixel Format:
    //---------------------------------------------------------
    int numberOfBytes;
    NSString *inputPixelFormat;
    if (inputTexture.pixelFormat == MTLPixelFormatBGRA8Unorm) {
        numberOfBytes = 1;
        inputPixelFormat = @"BGRA8";
    } else if (inputTexture.pixelFormat == MTLPixelFormatRGBA16Float) {
        inputPixelFormat = @"RGBAf16";
        numberOfBytes = 2;
    } else if (inputTexture.pixelFormat == MTLPixelFormatRGBA32Float) {
        inputPixelFormat = @"RGBAf";
        numberOfBytes = 4;
    } else {
        //---------------------------------------------------------
        // Output error message to Console:
        //---------------------------------------------------------
        NSString *errorMessage = [NSString stringWithFormat:@"BUG - Unsupported pixelFormat for inputTexture: %lu", (unsigned long)inputTexture.pixelFormat];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_UnsupportedPixelFormat
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Collect all the Parameters for Gyroflow:
    //---------------------------------------------------------
    const char*     xUniqueIdentifier          = [uniqueIdentifier UTF8String];
    uint32_t        xWidth                     = (uint32_t)inputTexture.width;
    uint32_t        xHeight                    = (uint32_t)inputTexture.height;
    const char*     xPixelFormat               = [inputPixelFormat UTF8String];
    const char*     xPath                      = [gyroflowPath UTF8String];
    const char*     xData                      = [gyroflowData UTF8String];
    int64_t         xTimestamp                 = [timestamp longLongValue];
    double          xFOV                       = [fov doubleValue];
    double          xSmoothness                = [smoothness doubleValue];
    double          xLensCorrection            = [lensCorrection doubleValue] / 100.0;
    double          xHorizonLock               = [horizonLock doubleValue];
    double          xHorizonRoll               = [horizonRoll doubleValue];
    double          xPositionOffsetX           = [positionOffsetX doubleValue];
    double          xPositionOffsetY           = [positionOffsetY doubleValue];
    double          xInputRotation             = [inputRotation doubleValue];
    double          xVideoRotation             = [videoRotation doubleValue];
    uint8_t         xFOVOverview               = [fovOverview unsignedCharValue];
    uint8_t         xDisableGyroflowStretch    = [disableGyroflowStretch unsignedCharValue];
    
    //---------------------------------------------------------
    // Trigger the Gyroflow Rust Function:
    //---------------------------------------------------------
    GyroflowRenderOptions renderOptions;
    getRenderDefaults(&renderOptions);
    if (params.renderOptions.length == sizeof(renderOptions)) {
        [params.renderOptions getBytes:&renderOptions length:sizeof(renderOptions)];
    }
    int ok;
    if (params.parameterValues.length > 0) {
        ok = processFrameWithParameters(xUniqueIdentifier, xWidth, xHeight, xPixelFormat, numberOfBytes,
            xPath, xData, xTimestamp, params.parameterValues.UTF8String, params.hostKeyframes.UTF8String,
            (__bridge void *)inputTexture, (__bridge void *)outputTexture, nil);
    } else {
        ok = processFrameWithKeyframes(
                          xUniqueIdentifier,                    // const char*
                          xWidth,                               // uint32_t
                          xHeight,                              // uint32_t
                          xPixelFormat,                         // const char*
                          numberOfBytes,                        // int
                          xPath,                                // const char*
                          xData,                                // const char*
                          xTimestamp,                           // int64_t
                          xFOV,                                 // double
                          xSmoothness,                          // double
                          xLensCorrection,                      // double
                          xHorizonLock,                         // double
                          xHorizonRoll,                         // double
                          xPositionOffsetX,                     // double
                          xPositionOffsetY,                     // double
                          xInputRotation,                       // double
                          xVideoRotation,                       // double
                          xFOVOverview,                         // uint8_t
                          xDisableGyroflowStretch,              // uint8_t
                          (__bridge void *)inputTexture,        // MTLTexture
                          (__bridge void *)outputTexture,       // MTLTexture
                          nil,                                  // Core selects the texture's Metal device
                          &renderOptions,
                          params.hostKeyframes.UTF8String
                          );
    }

    //---------------------------------------------------------
    // Gyroflow Core had an error, so abort:
    //---------------------------------------------------------
    if (!ok) {
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        return [self renderErrorMessageWithID:@"GyroflowCoreRenderError"
                             destinationImage:destinationImage
                                   fullHeight:fullHeight
                                    fullWidth:fullWidth
                                     outError:outError
                                 outputHeight:outputHeight
                                  outputWidth:outputWidth
                                 sourceImages:sourceImages];
    }
        
    return YES;
}

//---------------------------------------------------------
//
#pragma mark - Settings Menu
//
//---------------------------------------------------------

//---------------------------------------------------------
// BUTTON: 'Settings'
//---------------------------------------------------------
-(void)buttonSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        //---------------------------------------------------------
        // Get User Defaults:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        
        //---------------------------------------------------------
        // Create the menu:
        //---------------------------------------------------------
        NSMenu *settingsMenu = [[NSMenu alloc] initWithTitle:@"Settings"];
        
        //---------------------------------------------------------
        // Create the "Show Alerts" sub-menu:
        //---------------------------------------------------------
        NSMenu *disableAlertSubMenu = [[NSMenu alloc] initWithTitle:@"Disable Alerts"];
        
        //---------------------------------------------------------
        // "Show Alerts" Sub Menu Items:
        //---------------------------------------------------------
        {
            //---------------------------------------------------------
            // Load Preset/Lens Profile Success:
            //---------------------------------------------------------
            NSMenuItem *suppressLoadPresetLensProfileSuccess   = [[NSMenuItem alloc] initWithTitle:@"Load Preset/Lens Profile Success" action:@selector(toggleMenuItem:) keyEquivalent:@""];
            suppressLoadPresetLensProfileSuccess.identifier    = @"suppressLoadPresetLensProfileSuccess";
            suppressLoadPresetLensProfileSuccess.target        = self;
            suppressLoadPresetLensProfileSuccess.enabled       = YES;
            suppressLoadPresetLensProfileSuccess.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressLoadPresetLensProfileSuccess"]];
            [disableAlertSubMenu addItem:suppressLoadPresetLensProfileSuccess];
            
            //---------------------------------------------------------
            // No Lens Profile Detected:
            //---------------------------------------------------------
            NSMenuItem *suppressNoLensProfileDetected   = [[NSMenuItem alloc] initWithTitle:@"No Lens Profile Detected" action:@selector(toggleMenuItem:) keyEquivalent:@""];
            suppressNoLensProfileDetected.identifier    = @"suppressNoLensProfileDetected";
            suppressNoLensProfileDetected.target        = self;
            suppressNoLensProfileDetected.enabled       = YES;
            suppressNoLensProfileDetected.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressNoLensProfileDetected"]];
            [disableAlertSubMenu addItem:suppressNoLensProfileDetected];
            
            //---------------------------------------------------------
            // Request Sandbox Access:
            //---------------------------------------------------------
            NSMenuItem *suppressRequestSandboxAccessAlert   = [[NSMenuItem alloc] initWithTitle:@"Request Sandbox Access" action:@selector(toggleMenuItem:) keyEquivalent:@""];
            suppressRequestSandboxAccessAlert.identifier    = @"suppressRequestSandboxAccessAlert";
            suppressRequestSandboxAccessAlert.target        = self;
            suppressRequestSandboxAccessAlert.enabled       = YES;
            suppressRequestSandboxAccessAlert.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressRequestSandboxAccessAlert"]];
            [disableAlertSubMenu addItem:suppressRequestSandboxAccessAlert];
            
            //---------------------------------------------------------
            // Successfully Imported:
            //---------------------------------------------------------
            NSMenuItem *suppressSuccessfullyImported   = [[NSMenuItem alloc] initWithTitle:@"Successfully Imported" action:@selector(toggleMenuItem:) keyEquivalent:@""];
            suppressSuccessfullyImported.identifier    = @"suppressSuccessfullyImported";
            suppressSuccessfullyImported.target        = self;
            suppressSuccessfullyImported.enabled       = YES;
            suppressSuccessfullyImported.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressSuccessfullyImported"]];
            [disableAlertSubMenu addItem:suppressSuccessfullyImported];
            
            //---------------------------------------------------------
            // Successfully Reloaded:
            //---------------------------------------------------------
            NSMenuItem *suppressSuccessfullyReloaded   = [[NSMenuItem alloc] initWithTitle:@"Successfully Reloaded" action:@selector(toggleMenuItem:) keyEquivalent:@""];
            suppressSuccessfullyReloaded.identifier    = @"suppressSuccessfullyReloaded";
            suppressSuccessfullyReloaded.target        = self;
            suppressSuccessfullyReloaded.enabled       = YES;
            suppressSuccessfullyReloaded.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressSuccessfullyReloaded"]];
            [disableAlertSubMenu addItem:suppressSuccessfullyReloaded];
        }
        
        //---------------------------------------------------------
        // Add "Show Alerts" Sub Menu:
        //---------------------------------------------------------
        NSMenuItem *disableAlertSubMenuItem = [[NSMenuItem alloc] initWithTitle:@"Disabled Alerts" action:nil keyEquivalent:@""];
        [disableAlertSubMenuItem setSubmenu:disableAlertSubMenu];
        [settingsMenu addItem:disableAlertSubMenuItem];
        
        //---------------------------------------------------------
        // Add Separator:
        //---------------------------------------------------------
        NSMenuItem *separator   = [NSMenuItem separatorItem];
        separator.target        = self;
        separator.enabled       = YES;
        [settingsMenu addItem:separator];
        
        //---------------------------------------------------------
        // Grant Sandbox Access:
        //---------------------------------------------------------
        NSMenuItem *grantSandboxAccess = [[NSMenuItem alloc] initWithTitle:@"Grant Sandbox Access" action:@selector(pressGrantSandboxAccess:) keyEquivalent:@""];
        grantSandboxAccess.target = self;
        grantSandboxAccess.enabled = YES;
        [settingsMenu addItem:grantSandboxAccess];

        //---------------------------------------------------------
        // Reset Sandbox Access:
        //---------------------------------------------------------
        NSMenuItem *resetSandboxAccess = [[NSMenuItem alloc] initWithTitle:@"Reset Sandbox Access" action:@selector(pressResetSandboxAccess:) keyEquivalent:@""];
        resetSandboxAccess.target = self;
        resetSandboxAccess.enabled = YES;
        [settingsMenu addItem:resetSandboxAccess];
        
        //---------------------------------------------------------
        // Add Separator:
        //---------------------------------------------------------
        NSMenuItem *separatorB   = [NSMenuItem separatorItem];
        separatorB.target        = self;
        separatorB.enabled       = YES;
        [settingsMenu addItem:separatorB];
        
        //---------------------------------------------------------
        // Show Log File in Finder:
        //---------------------------------------------------------
        NSMenuItem *showLogFileInFinder    = [[NSMenuItem alloc] initWithTitle:@"Show Log Files in Finder" action:@selector(showLogFileInFinder:) keyEquivalent:@""];
        showLogFileInFinder.target         = self;
        showLogFileInFinder.enabled        = YES;
        [settingsMenu addItem:showLogFileInFinder];
        
        //---------------------------------------------------------
        // Reset Settings:
        //---------------------------------------------------------
        NSMenuItem *resetSettings       = [[NSMenuItem alloc] initWithTitle:@"Reset All Settings" action:@selector(resetSettings:) keyEquivalent:@""];
        resetSettings.target            = self;
        resetSettings.enabled           = YES;
        [settingsMenu addItem:resetSettings];

        //---------------------------------------------------------
        // Get the current mouse location:
        //---------------------------------------------------------
        NSPoint mouseLocation = [NSEvent mouseLocation];
        
        //---------------------------------------------------------
        // Show the menu at the current mouse location:
        //---------------------------------------------------------
        [settingsMenu popUpMenuPositioningItem:nil atLocation:mouseLocation inView:nil appearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    });
}

//---------------------------------------------------------
// Show Log File in Finder:
//---------------------------------------------------------
- (void)showLogFileInFinder:(id)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *applicationSupportDirectory = [paths firstObject];
    NSString* logPath = [applicationSupportDirectory stringByAppendingString:@"/FxPlug.log"];
    [[NSWorkspace sharedWorkspace] selectFile:logPath inFileViewerRootedAtPath:@""];
}

//---------------------------------------------------------
// Reset Settings:
//---------------------------------------------------------
- (void)resetSettings:(id)sender {
    //---------------------------------------------------------
    // Get User Defaults:
    //---------------------------------------------------------
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults removeObjectForKey:@"suppressLoadPresetLensProfileSuccess"];
    [userDefaults removeObjectForKey:@"suppressNoLensProfileDetected"];
    [userDefaults removeObjectForKey:@"suppressRequestSandboxAccessAlert"];
    [userDefaults removeObjectForKey:@"suppressSuccessfullyImported"];
    [userDefaults removeObjectForKey:@"suppressSuccessfullyReloaded"];
    
    [userDefaults removeObjectForKey:@"gyroFlowPreferencesBookmarkData"];
    [userDefaults removeObjectForKey:@"brawToolboxDocumentBookmarkData"];
        
    [userDefaults removeObjectForKey:@"lastReloadPath"];
    [userDefaults removeObjectForKey:@"lastImportGyroflowProjectPath"];
    [userDefaults removeObjectForKey:@"lastImportMediaPath"];
}

//---------------------------------------------------------
// Toggle Menu Item:
//---------------------------------------------------------
- (void)toggleMenuItem:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem *)sender;
    BOOL state = menuItem.state == NSControlStateValueOff; // NOTE: We want the opposite for the toggle.
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setBool:state forKey:menuItem.identifier];
}

//---------------------------------------------------------
// Menu Item: Grant Sandbox Access:
//---------------------------------------------------------
- (void)pressGrantSandboxAccess:(id)sender
{
    //---------------------------------------------------------
    // Display an open panel:
    //---------------------------------------------------------
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:NO];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:[NSURL fileURLWithPath:@"/Volumes/"]];
    [panel setPrompt:@"Grant Access"];
    [panel setMessage:@"Select a folder or drive then click 'Grant Access' to allow Gyroflow Toolbox access to it:"];
    NSModalResponse result = [panel runModal];
    if (result == NSModalResponseOK) {
        NSURL *url = [panel URL];
        
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
        
        //---------------------------------------------------------
        // There was a bookmark error:
        //---------------------------------------------------------
        if (bookmarkError != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to create security-scoped bookmark due to: %@", bookmarkError.localizedDescription];
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR: %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            return;
        }
        if (bookmark == nil) {
            NSString *errorMessage = @"Failed to create security-scoped bookmark due to an unknown error.";
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR: %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Write bookmark to preferences:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
        
        NSArray *globalBookmarks = [userDefaults objectForKey:@"globalBookmarks"];
        
        NSMutableArray *newGlobalBookmarks;
        
        if (globalBookmarks == nil) {
            newGlobalBookmarks = [NSMutableArray new];
        } else {
            newGlobalBookmarks = [globalBookmarks mutableCopy];
        }
        [newGlobalBookmarks addObject:bookmark];
        
        [userDefaults setObject:newGlobalBookmarks forKey:@"globalBookmarks"];
        
        NSLog(@"[Gyroflow Toolbox Renderer] Created new security-scoped bookmark: %@", [url path]);
    }
}

//---------------------------------------------------------
// Menu Item: Reset Sandbox Access:
//---------------------------------------------------------
- (void)pressResetSandboxAccess:(id)sender
{
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
    NSArray *emptyArray = [NSArray new];
    [userDefaults setObject:emptyArray forKey:@"globalBookmarks"];
    
    [self showAlertWithMessage:@"Sandbox Access Reset" info:@"All previously granted sandbox access has been revoked.\n\nYou will need to restart Final Cut Pro for this to take affect."];
}

//---------------------------------------------------------
//
#pragma mark - Buttons
//
//---------------------------------------------------------

//---------------------------------------------------------
// Custom Button View Pressed:
//---------------------------------------------------------
- (void)customButtonViewPressed:(UInt32)buttonID
{
    if (buttonID >= 700 && buttonID < 800) { [self performToolboxAction:buttonID]; return; }
    if (buttonID == kCB_LaunchGyroflow) {
        [self buttonLaunchGyroflow];
    } else if (buttonID == kCB_LoadLastGyroflowProject) {
        [self buttonLoadLastGyroflowProject];
    } else if (buttonID == kCB_ImportGyroflowProject) {
        [self buttonImportGyroflowProject];
    } else if (buttonID == kCB_ReloadGyroflowProject) {
        [self buttonReloadGyroflowProject];
    } else if (buttonID == kCB_ExportGyroflowProject) {
        [self buttonExportGyroflowProject];
    } else if (buttonID == kCB_ImportMediaFile) {
        [self buttonImportMediaFile];
    } else if (buttonID == kCB_RevealInFinder) {
        [self buttonRevealInFinder];
    } else if (buttonID == kCB_LoadPresetLensProfile) {
        [self buttonLoadPresetLensProfileIsImporting:NO];
    } else if (buttonID == kCB_OpenUserGuide) {
        [self buttonOpenUserGuide];
    } else if (buttonID == kCB_Settings) {
        [self buttonSettings];
    }
}

//---------------------------------------------------------
// BUTTON: 'Export Gyroflow Project'
//---------------------------------------------------------
- (void)buttonExportGyroflowProject {
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow Project Data:
    //---------------------------------------------------------
    NSString *gyroflowProjectData = nil;
    [paramGetAPI getStringParameterValue:&gyroflowProjectData fromParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Check that the Gyroflow Project is valid:
    //---------------------------------------------------------
    if (gyroflowProjectData == nil || [gyroflowProjectData isEqualToString:@""]) {
        [actionAPI endAction:self];
        NSString *errorMessage = @"There is currently no Gyroflow Project data loaded.\n\nPlease load a Gyroflow Project or Media File and try again.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"No Gyroflow Project Found" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // If the Gyroflow Project is base64 encoded, try to
    // decode it first:
    //---------------------------------------------------------
    NSData *base64EncodedData = [[NSData alloc] initWithBase64EncodedString:gyroflowProjectData options:0];
    if (base64EncodedData != nil) {
        NSString *decodedGyroflowData = [[NSString alloc] initWithData:base64EncodedData encoding:NSUTF8StringEncoding];
        if (decodedGyroflowData != nil) {
            gyroflowProjectData = [NSString stringWithString:decodedGyroflowData];
        }
    }

    // Bake the inspector's complete curves in Rust so exported projects render identically.
    id<FxTimingAPI_v4> timingAPI = [self.apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
    CMTime startTime = kCMTimeInvalid;
    [timingAPI startTimeForEffect:&startTime];
    NSData *state = nil;
    NSError *exportError = nil;
    if (!CMTIME_IS_NUMERIC(startTime) || ![self pluginState:&state atTime:startTime quality:kFxQuality_HIGH error:&exportError]) {
        [actionAPI endAction:self];
        [self showAlertWithMessage:@"Unable to Export Animation" info:exportError.localizedDescription ?: @"The clip timing is unavailable."];
        return;
    }
    GyroflowParameters *parameters = [NSKeyedUnarchiver unarchivedObjectOfClass:GyroflowParameters.class fromData:state error:&exportError];
    if (parameters.hostKeyframes.length > 0) {
        GyroflowRenderOptions options;
        getRenderDefaults(&options);
        if (parameters.renderOptions.length == sizeof(options)) [parameters.renderOptions getBytes:&options length:sizeof(options)];
        const char *exported = exportConfiguredProject(gyroflowProjectData.UTF8String, parameters.hostKeyframes.UTF8String, &options);
        NSString *document = [NSString stringWithUTF8String:exported];
        freeCString((char *)exported);
        if (!document || [document isEqualToString:@"FAIL"]) {
            [actionAPI endAction:self];
            [self showAlertWithMessage:@"Unable to Export Animation" info:@"Gyroflow could not prepare the current settings and keyframes for export."];
            return;
        }
        gyroflowProjectData = document;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow Project Path:
    //---------------------------------------------------------
    NSString *gyroflowProjectPath = nil;
    [paramGetAPI getStringParameterValue:&gyroflowProjectPath fromParameter:kCB_GyroflowProjectPath];
    
    //---------------------------------------------------------
    // Get the existing Gyroflow Project Path:
    //---------------------------------------------------------
    NSString *gyroflowProjectName = nil;
    [paramGetAPI getStringParameterValue:&gyroflowProjectName fromParameter:kCB_LoadedGyroflowProject];
    
    if (gyroflowProjectName.length > 0) {
        gyroflowProjectName = [gyroflowProjectName stringByAppendingString:@".gyroflow"];
    } else {
        gyroflowProjectName = @"Untitled.gyroflow";
    }
    
    //---------------------------------------------------------
    // Stop the Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Limit the file type to Gyroflow supported media files:
    //---------------------------------------------------------
    UTType *gyroflow                 = [UTType typeWithFilenameExtension:@"gyroflow"];
    NSArray *allowedContentTypes    = [NSArray arrayWithObjects:gyroflow, nil];
    
    //---------------------------------------------------------
    // Display Save Panel:
    //---------------------------------------------------------
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    
    [savePanel setTitle:@"Choose a Location to Save Your Gyroflow Project"];
    [savePanel setPrompt:@"Save"];
    [savePanel setNameFieldStringValue:gyroflowProjectName];
    [savePanel setDirectoryURL:[NSURL fileURLWithPath:gyroflowProjectPath]];
    [savePanel setAllowedContentTypes:allowedContentTypes];
    [savePanel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    
    //---------------------------------------------------------
    // Show the Save Panel:
    //---------------------------------------------------------
    [savePanel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            NSURL *fileURL = [savePanel URL];
            
            NSError *error = nil;
            BOOL succeeded = [gyroflowProjectData writeToURL:fileURL
                                                  atomically:YES
                                                    encoding:NSUTF8StringEncoding
                                                       error:&error];
            if (!succeeded) {
                //---------------------------------------------------------
                // Failed to save:
                //---------------------------------------------------------
                [actionAPI endAction:self];
                NSString *errorMessage = [NSString stringWithFormat:@"Failed to write the Gyroflow Project to '%@', due to:\n\n%@", [fileURL path], error.localizedDescription];
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            }
        }
    }];
}

//---------------------------------------------------------
// BUTTON: 'Open User Guide'
//---------------------------------------------------------
- (void)buttonOpenUserGuide {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSURL *url = [NSURL URLWithString:@"https://gyroflowtoolbox.io/how-to-use/"];
            [[NSWorkspace sharedWorkspace] openURL:url];
        }
    });
}

//---------------------------------------------------------
// BUTTON: 'Load Preset/Lens Profile'
//---------------------------------------------------------
- (void)buttonLoadPresetLensProfileIsImporting:(BOOL)isImporting {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] buttonLoadPresetLensProfileIsImporting Triggered!");
    //NSLog(@"[Gyroflow Toolbox Renderer] isImporting: %@", [NSNumber numberWithBool:isImporting]);
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil)
    {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow Project data:
    //---------------------------------------------------------
    NSString *gyroflowProjectData = nil;
    [paramGetAPI getStringParameterValue:&gyroflowProjectData fromParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // If the Gyroflow Project is base64 encoded, try to
    // decode it first:
    //---------------------------------------------------------
    NSData *base64EncodedData = [[NSData alloc] initWithBase64EncodedString:gyroflowProjectData options:0];
    if (base64EncodedData != nil) {
        NSString *decodedGyroflowData = [[NSString alloc] initWithData:base64EncodedData encoding:NSUTF8StringEncoding];
        if (decodedGyroflowData != nil) {
            gyroflowProjectData = [NSString stringWithString:decodedGyroflowData];
        }
    }
    
    //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProjectData: %@", gyroflowProjectData);
          
    if (gyroflowProjectData == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Please ensure you have a Gyroflow Project already loaded.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Failed to get Gyroflow Project" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the Lens Identifier from the Gyroflow Project:
    //---------------------------------------------------------
    NSString *loadedLensIdentifierInGyroflowProjectString = nil;
    const char* loadedLensIdentifierInGyroflowProject = getLensIdentifier([gyroflowProjectData UTF8String]);
    loadedLensIdentifierInGyroflowProjectString = [NSString stringWithUTF8String:loadedLensIdentifierInGyroflowProject];
    if (loadedLensIdentifierInGyroflowProject) freeCString((char *)loadedLensIdentifierInGyroflowProject);

    //---------------------------------------------------------
    // Get the Lens Profiles path:
    //---------------------------------------------------------
    NSBundle *mainBundle            = [NSBundle mainBundle];
    NSString *lensProfilesPath      = [mainBundle pathForResource:@"Lens Profiles" ofType:nil inDirectory:nil];
    NSURL *lensProfilesURL          = [NSURL fileURLWithPath:lensProfilesPath];
        
    //---------------------------------------------------------
    // Try match the Lens Identifier with a JSON file:
    //---------------------------------------------------------
    if (loadedLensIdentifierInGyroflowProjectString != nil) {
        
        //NSLog(@"[Gyroflow Toolbox Renderer] Try to match the Lens Identifier with a JSON file");
              
        NSString *path = self.lensProfilesLookup[loadedLensIdentifierInGyroflowProjectString];
        //NSLog(@"[Gyroflow Toolbox Renderer] lensProfilesLookup path: %@", path);
        
        if (path != nil) {
            lensProfilesURL = [NSURL fileURLWithPath:path];
        } else {
            NSLog(@"[Gyroflow Toolbox Renderer] WARNING - Failed to find matching identifier: %@", loadedLensIdentifierInGyroflowProjectString);
        }
    }
    
    //---------------------------------------------------------
    // Limit the file type to Gyroflow supported media files:
    //---------------------------------------------------------
    UTType *gyroflow                = [UTType typeWithFilenameExtension:@"gyroflow"];
    UTType *json                    = [UTType typeWithFilenameExtension:@"json"];
    NSArray *allowedContentTypes    = [NSArray arrayWithObjects:gyroflow, json, nil];
    
    //---------------------------------------------------------
    // Setup an NSOpenPanel:
    //---------------------------------------------------------
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setMessage:@"Please select the Preset or Lens Profile:"];
    [panel setPrompt:@"Open File"];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:lensProfilesURL];
    [panel setAllowedContentTypes:allowedContentTypes];
    [panel setExtensionHidden:NO];
    [panel setCanSelectHiddenExtension:YES];
    [panel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    
    //NSLog(@"[Gyroflow Toolbox Renderer] Preparing to open panel!");
    
    //---------------------------------------------------------
    // Open the panel:
    //---------------------------------------------------------
    NSModalResponse result = [panel runModal];
    if (result != NSModalResponseOK) {
        return;
    }
    
    NSURL *url = [panel URL];
    
    //---------------------------------------------------------
    // Start accessing security scoped resource:
    //---------------------------------------------------------
    if (![url startAccessingSecurityScopedResource]) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource during Load Preset/Lens Profile. This shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Process the file depending on the file type:
    //---------------------------------------------------------
    NSString *filePath              = [url path];
    NSString *extension             = [[url pathExtension] lowercaseString];
    NSString *loadResultString      = nil;
    
    BOOL isJSON = NO;
    if ([extension isEqualToString:@"json"]) {
        //---------------------------------------------------------
        // Attempt to load the JSON Lens Profile:
        //---------------------------------------------------------
        const char* loadResult = loadLensProfile(
                                                 [gyroflowProjectData UTF8String],
                                                 [filePath UTF8String]
                                                 );
        loadResultString = [NSString stringWithUTF8String: loadResult];
        if (loadResult) freeCString((char *)loadResult);
        isJSON = YES;
    } else {
        //---------------------------------------------------------
        // Attempt to load the Gyroflow Project Preset:
        //---------------------------------------------------------
        const char* loadResult = loadPreset(
                                            [gyroflowProjectData UTF8String],
                                            [filePath UTF8String]
                                            );
        loadResultString = [NSString stringWithUTF8String: loadResult];
        if (loadResult) freeCString((char *)loadResult);
    }
    
    //---------------------------------------------------------
    // Stop Accessing File:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
        
    //---------------------------------------------------------
    // Abort is failed:
    //---------------------------------------------------------
    if (loadResultString == nil || [loadResultString isEqualToString:@"FAIL"]) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Failed to load a Lens Profile or Preset.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Save the data to FxPlug as base64 encoded data:
    //---------------------------------------------------------
    NSData *loadResultStringData = [loadResultString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64EncodedString = [loadResultStringData base64EncodedStringWithOptions:0];
    [paramSetAPI setStringParameterValue:base64EncodedString toParameter:kCB_GyroflowProjectData];
    
    [self applyProjectDefaultsFromProject:loadResultString parameterAPI:paramSetAPI];

    //---------------------------------------------------------
    // Trash the cache!
    //---------------------------------------------------------
    trashCache();
        
    //---------------------------------------------------------
    // Show success message:
    //---------------------------------------------------------
    NSString *message = nil;
    
    if (isImporting) {
        if (isJSON) {
            message = @"The Gyroflow Project, and the selected Preset has been successfully imported into Final Cut Pro.\n\nYou can now adjust the parameters as required via the Video Inspector.";
        } else {
            message = @"The Gyroflow Project, and the selected Lens Profile has been successfully imported into Final Cut Pro.\n\nYou can now adjust the parameters as required via the Video Inspector.";
        }
    } else {
        if (isJSON) {
            message = @"The selected Preset has been successfully applied.";
        } else {
            message = @"The selected Lens Profile has been successfully applied.";
        }
    }
        
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"suppressLoadPresetLensProfileSuccess"]) {
        NSAlert *alert                  = [GyroflowAlertFactory makeAlert];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Imported!";
        alert.informativeText           = message;
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressLoadPresetLensProfileSuccess"];
            }
        }];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
}

//---------------------------------------------------------
// BUTTON: 'Reveal in Finder'
//---------------------------------------------------------
- (void)buttonRevealInFinder {
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow project path:
    //---------------------------------------------------------
    NSString *existingProjectPath = nil;
    [paramGetAPI getStringParameterValue:&existingProjectPath fromParameter:kCB_GyroflowProjectPath];
    
    NSURL *existingProjectURL = [NSURL fileURLWithPath:existingProjectPath];
    
    if (existingProjectURL != nil) {
        [[NSWorkspace sharedWorkspace] selectFile:[existingProjectURL path] inFileViewerRootedAtPath:@""];
    } else {
        [self showAlertWithMessage:@"No Gyroflow Project Found" info:@"Please ensure you have a Gyroflow Project already loaded."];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
}

//---------------------------------------------------------
// BUTTON: 'Launch Gyroflow'
//---------------------------------------------------------
- (void)buttonImportMediaFile {
    [self importMediaWithOptionalURL:nil completionHandler:nil];
}

//---------------------------------------------------------
// BUTTON: 'Launch Gyroflow'
//---------------------------------------------------------
- (void)buttonLaunchGyroflow {
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Show Error Message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    NSString *pathToOpen = nil;
    
    //---------------------------------------------------------
    // Get the existing Media path:
    //---------------------------------------------------------
    NSString *existingMediaPath = nil;
    BOOL isMediaFile = NO;
    [paramGetAPI getStringParameterValue:&existingMediaPath fromParameter:kCB_MediaPath];
    
    if (existingMediaPath != nil) {
        isMediaFile = YES;
        pathToOpen = [NSString stringWithString:existingMediaPath];
    } else {
        //---------------------------------------------------------
        // Get the existing Gyroflow project path:
        //---------------------------------------------------------
        NSString *existingProjectPath = nil;
        [paramGetAPI getStringParameterValue:&existingProjectPath fromParameter:kCB_GyroflowProjectPath];
        pathToOpen = [NSString stringWithString:existingProjectPath];
    }
    
    //---------------------------------------------------------
    // Open Gyroflow or the current Gyroflow Project:
    //---------------------------------------------------------
    NSString *bundleIdentifier = @"xyz.gyroflow";
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    
    if (appURL == nil) {
        //---------------------------------------------------------
        // Gyroflow is not installed:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] Could not find Gyroflow Installation");
        [actionAPI endAction:self];
        [self showAlertWithMessage:@"Gyroflow Application Not Found" info:@"The Gyroflow application could not be found on your system.\n\nGyroflow is a free and open-source application, that is separate and independent of this Gyroflow Toolbox plugin.\n\nYou can download the latest version of Gyroflow from:\n\nhttps://gyroflow.xyz"];
        return;
    }
    
    if (pathToOpen == nil || [pathToOpen isEqualToString:@""]) {
        //---------------------------------------------------------
        // No Media file or Gyroflow Project loaded:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] WARNING - No existing media or Gyroflow project was found so loading blank Gyroflow.");
        [[NSWorkspace sharedWorkspace] openURL:appURL];
        
    } else {
        //---------------------------------------------------------
        // Get the encoded bookmark string:
        //---------------------------------------------------------
        NSString *encodedBookmark;
        
        if (isMediaFile) {
            [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_MediaBookmarkData];
        } else {
            [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_GyroflowProjectBookmarkData];
        }
        
        //---------------------------------------------------------
        // Make sure there's actually encoded bookmark data:
        //---------------------------------------------------------
        if ([encodedBookmark isEqualToString:@""]) {
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Encoded security-scoped bookmark is empty when trying to launch Gyroflow.");
            [[NSWorkspace sharedWorkspace] openURL:appURL];
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // Decode the Base64 bookmark data:
        //---------------------------------------------------------
        NSData *decodedBookmark = [[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                                      options:0];
        
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
            NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to resolve security-scoped bookmark when trying to launch Gyroflow due to: %@", bookmarkError.localizedDescription);
            [[NSWorkspace sharedWorkspace] openURL:appURL];
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // Read the Gyroflow Project Data from File:
        //---------------------------------------------------------
        if (![url startAccessingSecurityScopedResource]) {
            NSLog(@"[Gyroflow Toolbox Renderer] Failed to start security scoped resource: %@", url);
            [[NSWorkspace sharedWorkspace] openURL:appURL];
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // This is depreciated, but there's no better way to do
        // it in a sandbox sadly without prompting for access
        // to the Gyroflow Application:
        //---------------------------------------------------------
        #pragma GCC diagnostic push
        #pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        [[NSWorkspace sharedWorkspace] openFile:[url path] withApplication:@"Gyroflow"];
        #pragma GCC diagnostic pop
        
        //---------------------------------------------------------
        // Stop Accessing Security Scoped Resource:
        //---------------------------------------------------------
        [url stopAccessingSecurityScopedResource];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
}

//---------------------------------------------------------
// BUTTON: 'Import Gyroflow Project'
//---------------------------------------------------------
- (void)buttonImportGyroflowProject {
    [self importGyroflowProjectWithOptionalURL:nil completionHandler:nil];
}

//---------------------------------------------------------
// BUTTON: 'Load Last Gyroflow Project'
//---------------------------------------------------------
- (void)buttonLoadLastGyroflowProject {
    //NSLog(@"[Gyroflow Toolbox Renderer] Load Last Gyroflow Project Pressed!");
    
    if ([self canReadGyroflowPreferencesFile]) {
        //---------------------------------------------------------
        // We can read the Gyroflow Preferences file:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] We can read the preferences file.");
        [self readLastProjectFromGyroflowPreferencesFile];
    } else {
        //---------------------------------------------------------
        // We can't read the Gyroflow Preferences file, so lets
        // try get sandbox access:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] We can't read the preferences file.");
        NSURL* gyroflowPlistURL = [self getGyroflowPreferencesFileURL];
        [self requestSandboxAccessAlertWithURL:gyroflowPlistURL];
    }
}

//---------------------------------------------------------
// BUTTON: 'Reload Gyroflow Project'
//---------------------------------------------------------
- (void)buttonReloadGyroflowProject {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] BUTTON PRESSED: Reload Gyroflow Project");
    
    //---------------------------------------------------------
    // Setup User Defaults:
    //---------------------------------------------------------
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    //---------------------------------------------------------
    // Trash all the caches in Rust land:
    //---------------------------------------------------------
    trashCache();
    //uint32_t cacheSize = trashCache();
    //NSLog(@"[Gyroflow Toolbox Renderer] Rust MANAGER_CACHE size after trashing (should be zero): %u", cacheSize);
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the encoded bookmark string:
    //---------------------------------------------------------
    NSString *encodedBookmark;
    [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_GyroflowProjectBookmarkData];
    //NSLog(@"[Gyroflow Toolbox Renderer] encodedBookmark: %@", encodedBookmark);
    
    //---------------------------------------------------------
    // Make sure there's actually encoded bookmark data. If
    // there's no bookmark, lets try the file path instead:
    //---------------------------------------------------------
    if (encodedBookmark == nil || [encodedBookmark isEqualToString:@""]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] encodedBookmark is empty, so lets try file path instead...");
        
        //---------------------------------------------------------
        // Get the File Path:
        //---------------------------------------------------------
        NSString *gyroflowProjectPath;
        [paramGetAPI getStringParameterValue:&gyroflowProjectPath fromParameter:kCB_GyroflowProjectPath];
        //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProjectPath: %@", gyroflowProjectPath);
        
        //---------------------------------------------------------
        // If there's no path, then abort:
        //---------------------------------------------------------
        if ([gyroflowProjectPath isEqualToString:@""]) {
            [self showAlertWithMessage:@"No active Gyroflow Project" info:@"There is currently no active Gyroflow Project loaded.\n\nEither you haven't imported a Gyroflow Project yet, or you imported a Media File that doesn't have a corresponding Gyroflow Project.\n\nIf you imported a Media File, you can use the 'Export Gyroflow Project' to save a Gyroflow Project locally."];
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // Get Gyroflow Project URL & Filename:
        //---------------------------------------------------------
        NSURL *gyroflowProjectURL           = [NSURL fileURLWithPath:gyroflowProjectPath];
        NSString *gyroflowProjectFilename   = [gyroflowProjectURL lastPathComponent];
        
        //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProjectURL: %@", gyroflowProjectURL);
        //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProjectFilename: %@", gyroflowProjectFilename);
        
        //---------------------------------------------------------
        // Check to see if the Gyroflow Project path actually
        // exists:
        //---------------------------------------------------------
        NSString *desktopPath = [[self getUserHomeDirectoryPath] stringByAppendingString:@"/Desktop/"];
        NSURL *defaultFolderURL = [NSURL fileURLWithPath:desktopPath];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if ([fileManager fileExistsAtPath:gyroflowProjectPath]) {
            //---------------------------------------------------------
            // Gyroflow Project file exists:
            //---------------------------------------------------------
            defaultFolderURL = gyroflowProjectURL;
        } else {
            //---------------------------------------------------------
            // If the Gyroflow Project path doesn't exist, try the
            // media folder instead:
            //---------------------------------------------------------
            BOOL validMediaPath = NO;
            NSString *mediaPath;
            [paramGetAPI getStringParameterValue:&mediaPath fromParameter:kCB_MediaPath];
            if (mediaPath != nil && ![mediaPath isEqualToString:@""]) {
                NSString *mediaPathFolder = [mediaPath stringByDeletingLastPathComponent];
                if ([fileManager fileExistsAtPath:mediaPathFolder]) {
                    defaultFolderURL = [NSURL fileURLWithPath:mediaPathFolder];
                    validMediaPath = YES;
                }
            }
            
            //---------------------------------------------------------
            // If the Media Path doesn't exist either, then use the
            // last known good path:
            //---------------------------------------------------------
            if (!validMediaPath) {
                NSString *lastReloadPath = [userDefaults stringForKey:@"lastReloadPath"];
                if ([fileManager fileExistsAtPath:lastReloadPath]) {
                    //---------------------------------------------------------
                    // Use last Reload Path:
                    //---------------------------------------------------------
                    defaultFolderURL = [NSURL fileURLWithPath:lastReloadPath];
                }
            }
        }
        
        //---------------------------------------------------------
        // Limit the file type to .gyroflow files:
        //---------------------------------------------------------
        UTType *gyroflowExtension       = [UTType typeWithFilenameExtension:@"gyroflow"];
        NSArray *allowedContentTypes    = [NSArray arrayWithObject:gyroflowExtension];
                
        //---------------------------------------------------------
        // Setup an NSOpenPanel:
        //---------------------------------------------------------
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        [panel setCanChooseDirectories:NO];
        [panel setCanCreateDirectories:YES];
        [panel setCanChooseFiles:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setDirectoryURL:defaultFolderURL];
        [panel setNameFieldStringValue:gyroflowProjectFilename];
        [panel setAllowedContentTypes:allowedContentTypes];
        [panel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
        
        //---------------------------------------------------------
        // Open the panel:
        //---------------------------------------------------------
        NSModalResponse result = [panel runModal];
        if (result != NSModalResponseOK) {
            //---------------------------------------------------------
            // Open panel cancelled:
            //---------------------------------------------------------
            //NSLog(@"[Gyroflow Toolbox Renderer] Open Panel Cancelled");
            
            //---------------------------------------------------------
            // Stop Action API:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // Start accessing security scoped resource:
        //---------------------------------------------------------
        NSURL *openPanelURL = [panel URL];
        //NSLog(@"[Gyroflow Toolbox Renderer] openPanelURL: %@", openPanelURL);
        
        //---------------------------------------------------------
        // Save path for next time...
        //---------------------------------------------------------
        [userDefaults setObject:[[openPanelURL path] stringByDeletingLastPathComponent] forKey:@"lastReloadPath"];
        
        BOOL startedOK = [openPanelURL startAccessingSecurityScopedResource];
        if (startedOK == NO) {
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            return;
        }
        
        //---------------------------------------------------------
        // Create a Security Scope Bookmark, so we can reload
        // later:
        //---------------------------------------------------------
        NSError *bookmarkError = nil;
        NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
        NSData *bookmark = [openPanelURL bookmarkDataWithOptions:bookmarkOptions
                                  includingResourceValuesForKeys:nil
                                                   relativeToURL:nil
                                                           error:&bookmarkError];
        
        //---------------------------------------------------------
        // There was an error creating the bookmark:
        //---------------------------------------------------------
        if (bookmarkError != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API & Stop Accessing Resource:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            [openPanelURL stopAccessingSecurityScopedResource];
            return;
        }
        
        //---------------------------------------------------------
        // The bookmark is nil:
        //---------------------------------------------------------
        if (bookmark == nil) {
            NSString *errorMessage = @"Bookmark data is nil. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API & Stop Accessing Resource:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            [openPanelURL stopAccessingSecurityScopedResource];
            return;
        }
        
        //---------------------------------------------------------
        // Get the Gyroflow Project strings from the
        // Open Panel URL:
        //---------------------------------------------------------
        NSString *selectedGyroflowProjectFile            = [[openPanelURL lastPathComponent] stringByDeletingPathExtension];
        NSString *selectedGyroflowProjectPath            = [openPanelURL path];
        NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
        
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectFile: %@", selectedGyroflowProjectFile);
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectPath: %@", selectedGyroflowProjectPath);
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectBookmarkData: %@", selectedGyroflowProjectBookmarkData);
        
        //---------------------------------------------------------
        // Read the Gyroflow Project Data from File:
        //---------------------------------------------------------
        NSError *readError = nil;
        NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:openPanelURL encoding:NSUTF8StringEncoding error:&readError];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectData: %@", selectedGyroflowProjectData);
        
        //---------------------------------------------------------
        // There was an error reading the Gyroflow Project file:
        //---------------------------------------------------------
        if (readError != nil) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to read Gyroflow Project File due to:\n\n%@", [readError localizedDescription]];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API & Stop Accessing Resource:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            [openPanelURL stopAccessingSecurityScopedResource];
            return;
        }
        
        //---------------------------------------------------------
        // Before we attempt to check the Gyroflow Project, we need
        // to grant sandbox access to the media file if it exists:
        //---------------------------------------------------------
        NSString *mediaBookmarkDataString = nil;
        [paramGetAPI getStringParameterValue:&mediaBookmarkDataString fromParameter:kCB_MediaBookmarkData];
        //NSLog(@"[Gyroflow Toolbox Renderer] mediaBookmarkDataString: %@", mediaBookmarkDataString);
        
        //---------------------------------------------------------
        // If there's a bookmark for the media, lets try load it:
        //---------------------------------------------------------
        NSURL *decodedMediaBookmarkURL = nil;
        if (mediaBookmarkDataString != nil && ![mediaBookmarkDataString isEqualToString:@""]) {
            //---------------------------------------------------------
            // Decode the Base64 bookmark data:
            //---------------------------------------------------------
            NSData *decodedBookmark = [[NSData alloc] initWithBase64EncodedString:mediaBookmarkDataString
                                                                          options:0];

            //---------------------------------------------------------
            // Resolve the decoded bookmark data into a
            // security-scoped URL:
            //---------------------------------------------------------
            NSError *bookmarkError  = nil;
            BOOL isStale            = NO;
            
            decodedMediaBookmarkURL = [NSURL URLByResolvingBookmarkData:decodedBookmark
                                                                options:NSURLBookmarkResolutionWithSecurityScope
                                                          relativeToURL:nil
                                                    bookmarkDataIsStale:&isStale
                                                                  error:&bookmarkError];
            
            //---------------------------------------------------------
            // Continue if there's no error...
            //---------------------------------------------------------
            if (bookmarkError == nil) {
                if ([decodedMediaBookmarkURL startAccessingSecurityScopedResource]) {
                    //NSLog(@"[Gyroflow Toolbox Renderer] Can access media: %@", [decodedMediaBookmarkURL path]);
                }
                //else
                //{
                    //NSLog(@"[Gyroflow Toolbox Renderer] Cannot access media: %@", [decodedMediaBookmarkURL path]);
                //}
            }
        }
        
        //---------------------------------------------------------
        // Make sure there's Gyro Data in the Gyroflow Project:
        //---------------------------------------------------------
        const char* hasData = doesGyroflowProjectContainStabilisationData([selectedGyroflowProjectData UTF8String]);
        NSString *hasDataResult = [NSString stringWithUTF8String: hasData];
        if (hasData) freeCString((char *)hasData);

        //NSLog(@"[Gyroflow Toolbox Renderer] doesGyroflowProjectContainStabilisationData: %@", hasDataResult);
        if (hasDataResult == nil || ![hasDataResult isEqualToString:@"YES"]) {
            NSString *errorMessage = @"The Gyroflow file you imported doesn't seem to contain any gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including gyro data)' option.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"Gyro Data Not Found." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API & Stop Accessing Resource:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            [openPanelURL stopAccessingSecurityScopedResource];
            return;
        }
        
        //---------------------------------------------------------
        // Stop accessing media file:
        //---------------------------------------------------------
        if (decodedMediaBookmarkURL != nil) {
            [decodedMediaBookmarkURL stopAccessingSecurityScopedResource];
        }
        
        //---------------------------------------------------------
        // Load the Parameter Set API:
        //---------------------------------------------------------
        id<FxParameterSettingAPI_v5> paramSetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
        if (paramSetAPI == nil)
        {
            NSString *errorMessage = @"Unable to retrieve 'FxParameterSettingAPI_v5'.\n\nThis shouldn't happen, so it's probably a bug.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Stop Action API & Stop Accessing Resource:
            //---------------------------------------------------------
            [actionAPI endAction:self];
            [openPanelURL stopAccessingSecurityScopedResource];
            return;
        }
        
        //---------------------------------------------------------
        // Generate a new unique identifier:
        //---------------------------------------------------------
        NSUUID *uuid = [NSUUID UUID];
        NSString *uniqueIdentifier = uuid.UUIDString;
        [paramSetAPI setStringParameterValue:uniqueIdentifier toParameter:kCB_UniqueIdentifier];
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Path':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectPath toParameter:kCB_GyroflowProjectPath];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectPath: %@", selectedGyroflowProjectPath);
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Bookmark Data':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectBookmarkData toParameter:kCB_GyroflowProjectBookmarkData];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectBookmarkData: %@", selectedGyroflowProjectBookmarkData);
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Data':
        //---------------------------------------------------------
        NSData *loadResultStringData = [selectedGyroflowProjectData dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64EncodedString = [loadResultStringData base64EncodedStringWithOptions:0];
        [paramSetAPI setStringParameterValue:base64EncodedString toParameter:kCB_GyroflowProjectData];
        
        //---------------------------------------------------------
        // Update 'Loaded Gyroflow Project' Text Box:
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectFile: %@", selectedGyroflowProjectFile);
        
        //---------------------------------------------------------
        // Show success message:
        //---------------------------------------------------------
        [self showSuccessfullyReloadedAlert];
        
        //---------------------------------------------------------
        // Stop Action API & Stop Accessing Resource:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        [openPanelURL stopAccessingSecurityScopedResource];
        return;
    }
    
    //---------------------------------------------------------
    // Decode the Base64 bookmark data:
    //---------------------------------------------------------
    NSData *decodedBookmark = [[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                                  options:0];
    
    //---------------------------------------------------------
    // Resolve the decoded bookmark data into a
    // security-scoped URL:
    //---------------------------------------------------------
    NSError *bookmarkError  = nil;
    BOOL isStale            = NO;
    
    NSURL *decodedBookmarkURL = [NSURL URLByResolvingBookmarkData:decodedBookmark
                                                          options:NSURLBookmarkResolutionWithSecurityScope
                                                    relativeToURL:nil
                                              bookmarkDataIsStale:&isStale
                                                            error:&bookmarkError];
    
    //---------------------------------------------------------
    // If there's a bookmark error, then abort:
    //---------------------------------------------------------
    if (bookmarkError != nil) {
        //---------------------------------------------------------
        // Show an error message:
        //---------------------------------------------------------
        NSString *message   = @"An error has occurred.";
        NSString *info      = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", info);
        [self showAlertWithMessage:message info:info];
        
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil) {
        //---------------------------------------------------------
        // Show an error message:
        //---------------------------------------------------------
        NSString *message   = @"An error has occurred.";
        NSString *info      = @"Unable to retrieve 'FxParameterSettingAPI_v5'.\n\nThis shouldn't happen, so it's probably a bug.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", info);
        [self showAlertWithMessage:message info:info];
        
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        return;
    }
    
    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    [decodedBookmarkURL startAccessingSecurityScopedResource];
    
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:decodedBookmarkURL encoding:NSUTF8StringEncoding error:&readError];
    
    //---------------------------------------------------------
    // Stop accessing security scoped bookmark:
    //---------------------------------------------------------
    [decodedBookmarkURL stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // If there was a problem reading the file:
    //---------------------------------------------------------
    if (readError != nil) {
        //---------------------------------------------------------
        // Show an error message:
        //---------------------------------------------------------
        NSString *message   = @"An error has occurred.";
        NSString *info      = [NSString stringWithFormat:@"Failed to read Gyroflow Project file due to:\n\n%@", [readError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", info);
        [self showAlertWithMessage:message info:info];
        
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        return;
    }
    
    //---------------------------------------------------------
    // Update 'Gyroflow Project Data':
    //---------------------------------------------------------
    NSData *loadResultStringData = [selectedGyroflowProjectData dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64EncodedString = [loadResultStringData base64EncodedStringWithOptions:0];
    [paramSetAPI setStringParameterValue:base64EncodedString toParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Generate a new unique identifier:
    //---------------------------------------------------------
    NSUUID *uuid = [NSUUID UUID];
    NSString *uniqueIdentifier = uuid.UUIDString;
    [paramSetAPI setStringParameterValue:uniqueIdentifier toParameter:kCB_UniqueIdentifier];
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Show success message:
    //---------------------------------------------------------
    [self showSuccessfullyReloadedAlert];
}

//---------------------------------------------------------
// Show Successfully Reloaded Alert:
//---------------------------------------------------------
- (void)showSuccessfullyReloadedAlert {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"suppressSuccessfullyReloaded"]) {
        NSAlert *alert                  = [GyroflowAlertFactory makeAlert];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Reloaded!";
        alert.informativeText           = @"The Gyroflow Project has been successfully reloaded from disk.";
        alert.showsSuppressionButton    = YES;

        [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressSuccessfullyReloaded"];
            }
        }];
    }
}

//---------------------------------------------------------
//
#pragma mark - Import Dropped Clip
//
//---------------------------------------------------------

//---------------------------------------------------------
// Import Dropped Media:
//---------------------------------------------------------
- (void)importDroppedMedia:(NSData*)bookmarkData {
        
    //---------------------------------------------------------
    // Resolve the security-scope bookmark:
    //---------------------------------------------------------
    NSError *bookmarkError = nil;
    BOOL isStale = NO;
    
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmarkData
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&isStale
                                             error:&bookmarkError];
    
    if (bookmarkError != nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to read security-scoped bookmark due to: %@", bookmarkError);
        return;
    }
    
    if (isStale) {
        NSLog(@"[Gyroflow Toolbox Renderer] WARNING - Bookmark is stale: %@", [url path]);
    }
    
    if (![url startAccessingSecurityScopedResource]) {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Could not start accessing the security-scoped bookmark.");
        return;
    }
    
    //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia URL: %@", [url path]);
    
    //---------------------------------------------------------
    // Check to see if we can actually read file:
    //---------------------------------------------------------
    /*
    if ([[NSFileManager defaultManager] isReadableFileAtPath:[url path]]) {
        NSLog(@"[Gyroflow Toolbox Renderer] Can read file: %@", [url path]);
    } else {
        NSLog(@"[Gyroflow Toolbox Renderer] Failed to read file: %@", [url path]);
    }
    */
    
    NSString *extension = [[url pathExtension] lowercaseString];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([extension isEqualToString:@"gyroflow"]) {
        //---------------------------------------------------------
        // If the dragged file is a Gyroflow file, try load it:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Gyroflow Project!");
        [self importGyroflowProjectWithOptionalURL:url completionHandler:nil];
    } else {
        //---------------------------------------------------------
        // If the dragged file is a Media file, check if there's
        // a Gyroflow Project next to it first:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File!");
        NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
        //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
        if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
            //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with a Gyroflow Project next to it.");
            [self importGyroflowProjectWithOptionalURL:gyroflowUrl completionHandler:^{
                //---------------------------------------------------------
                // Stop accessing the security scoped resource:
                //---------------------------------------------------------
                //NSLog(@"[Gyroflow Toolbox Renderer] COMPLETION HANDLER TRIGGERED!");
                [url stopAccessingSecurityScopedResource];
            }];
        } else {
            //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with no Gyroflow Project next to it.");
            [self importMediaWithOptionalURL:url completionHandler:^{
                //---------------------------------------------------------
                // Stop accessing the security scoped resource:
                //---------------------------------------------------------
                //NSLog(@"[Gyroflow Toolbox Renderer] COMPLETION HANDLER TRIGGERED!");
                [url stopAccessingSecurityScopedResource];
            }];
        }
    }
}

//---------------------------------------------------------
// Import Dropped Clip:
//---------------------------------------------------------
- (void)importDroppedClip:(NSString*)fcpxmlString {
    
    NSURL *url = nil;
    
    NSError *error;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithXMLString:fcpxmlString options:0 error:&error];
    
    //---------------------------------------------------------
    // Abort if there's an error processing the XML document:
    //---------------------------------------------------------
    if (error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to parse the FCPXML due to:\n\n%@", error.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAsyncAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // It's a BRAW Toolbox Clip:
    //---------------------------------------------------------
    if ([self isValidBRAWToolboxString:fcpxmlString]) {
        
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a BRAW clip!");
        
        BRAWToolboxXMLReader *reader = [[BRAWToolboxXMLReader alloc] init];
        NSDictionary *result = [reader readXML:fcpxmlString];
        
        if (![result isKindOfClass:[NSDictionary class]]) {
            [self showAlertWithMessage:@"An error has occurred" info:@"Failed to get the media path from the BRAW Toolbox Clip."];
            return;
        }
                
        //NSLog(@"[Gyroflow Toolbox Renderer] result: %@", result);
        
        NSString *filePath = result[@"File Path"];
        NSString *bookmarkData = result[@"Bookmark Data"];
        [self importBRAWToolboxClipWithPath:filePath bookmarkDataString:bookmarkData];
        
        return;
    }
    
    //---------------------------------------------------------
    // It's not a BRAW Toolbox Clip:
    //---------------------------------------------------------
    //NSLog(@"[Gyroflow Toolbox Renderer] It's NOT a BRAW clip!");
    
    NSArray *mediaRepNodes = [xmlDoc nodesForXPath:@"//media-rep" error:&error];
    
    //---------------------------------------------------------
    // Abort if we can't get a media-rep node:
    //---------------------------------------------------------
    if (error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Error extracting media-rep nodes:\n\n%@", error.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAsyncAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    for (NSXMLElement *node in mediaRepNodes) {
        NSString *src = [[node attributeForName:@"src"] stringValue];
        if (src) {
            url = [NSURL URLWithString:src];
        }
    }
    
    //---------------------------------------------------------
    // Abort if there's no valid URL:
    //---------------------------------------------------------
    if (url == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get the media path from the FCPXML: %@", fcpxmlString);
        [self showAsyncAlertWithMessage:@"An error has occurred" info:@"Failed to get the media path from the FCPXML."];
        return;
    }
    
    NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    //---------------------------------------------------------
    // Check if there's an existing Gyroflow Project:
    //---------------------------------------------------------
    if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
        [self importGyroflowProjectWithOptionalURL:gyroflowUrl completionHandler:nil];
    } else {
        [self importMediaWithOptionalURL:url completionHandler:nil];
    }
    
    return;
}

//---------------------------------------------------------
//
#pragma mark - Open Last Gyroflow Project
//
//---------------------------------------------------------

//---------------------------------------------------------
// Request Sandbox access alert:
//---------------------------------------------------------
- (void)requestSandboxAccessAlertWithURL:(NSURL*)gyroflowPlistURL {
    //---------------------------------------------------------
    // Show popup with instructions:
    //---------------------------------------------------------
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"suppressRequestSandboxAccessAlert"]) {
        NSAlert *alert                  = [GyroflowAlertFactory makeAlert];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Permission Required";
        alert.informativeText           = @"Gyroflow Toolbox requires explicit permission to access your Gyroflow Preferences, so that it can determine the last opened project.\n\nPlease click 'Grant Access' on the next Open Folder window to continue.";
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressRequestSandboxAccessAlert"];
            }
            [self requestSandboxAccessWithURL:gyroflowPlistURL];
        }];
    } else {
        [self requestSandboxAccessWithURL:gyroflowPlistURL];
    }
}

//---------------------------------------------------------
// Request Sandbox access to the Gyroflow Preferences file:
//---------------------------------------------------------
- (void)requestSandboxAccessWithURL:(NSURL*)gyroflowPlistURL {
    //---------------------------------------------------------
    // Display an open panel:
    //---------------------------------------------------------
    UTType *plistType               = [UTType typeWithIdentifier:@"com.apple.property-list"];
    NSArray *allowedContentTypes    = [NSArray arrayWithObject:plistType];
    
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:NO];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:gyroflowPlistURL];
    [panel setAllowedContentTypes:allowedContentTypes];
    [panel setPrompt:@"Grant Access"];
    [panel setMessage:@"Please click 'Grant Access' to allow access to the Gyroflow Preferences file:"];
    
    [panel beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result){
        if (result != NSModalResponseOK) {
            return;
        }
        
        NSURL *url = [panel URL];
        [url startAccessingSecurityScopedResource];
        
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
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to create a security-scoped bookmark due to the following error:\n\n %@", [bookmarkError localizedDescription]];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            [url stopAccessingSecurityScopedResource];
            return;
        }
        
        if (bookmark == nil) {
            [self showAlertWithMessage:@"An error has occurred" info:@"Failed to create a security-scoped bookmark due to the Bookmark being 'nil' and the error message is also being 'nil'"];
            [url stopAccessingSecurityScopedResource];
            return;
        }
        
        //NSLog(@"[Gyroflow Toolbox Renderer] Bookmark created successfully for: %@", [url path]);
        
        NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
        [userDefaults setObject:bookmark forKey:@"gyroFlowPreferencesBookmarkData"];

        [url stopAccessingSecurityScopedResource];
        
        [self readLastProjectFromGyroflowPreferencesFile];
    }];
}

//---------------------------------------------------------
// Can we read the Gyroflow Preferences File?
//---------------------------------------------------------
- (BOOL)canReadGyroflowPreferencesFile {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
    NSData *gyroFlowPreferencesBookmarkData = [userDefaults dataForKey:@"gyroFlowPreferencesBookmarkData"];
    
    if (gyroFlowPreferencesBookmarkData == nil) {
        return NO;
    }
    
    BOOL staleBookmark;
    NSURL *url = nil;
    NSError *bookmarkError = nil;
    url = [NSURL URLByResolvingBookmarkData:gyroFlowPreferencesBookmarkData
                                    options:NSURLBookmarkResolutionWithSecurityScope
                              relativeToURL:nil
                        bookmarkDataIsStale:&staleBookmark
                                      error:&bookmarkError];
    
    if (bookmarkError != nil) {
        //NSLog(@"[Gyroflow Toolbox Renderer] Failed to read Gyroflow Preferences Bookmark Data: %@", bookmarkError.localizedDescription);
        return NO;
    }
    
    if (staleBookmark) {
        //NSLog(@"[Gyroflow Toolbox Renderer] Stale Gyroflow Preferences Bookmark.");
        return NO;
    }
    
    if (url == nil) {
        //NSLog(@"[Gyroflow Toolbox Renderer] Gyroflow Preferences Bookmark is nil.");
        return NO;
    }
            
    if (![url startAccessingSecurityScopedResource]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] Failed to start accessing the security scope resource for the Gyroflow Preferences.");
        return NO;
    }
    
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfURL:url];
    
    [url stopAccessingSecurityScopedResource];
    
    if (![preferences isKindOfClass:[NSDictionary class]]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] Gyroflow Preferences Dictionary is nil.");
        return NO;
    }
    
    return YES;
}

//---------------------------------------------------------
// Read Last Project from Gyroflow Preferences File:
//---------------------------------------------------------
- (void)readLastProjectFromGyroflowPreferencesFile {
    
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
    NSData *gyroFlowPreferencesBookmarkData = [userDefaults dataForKey:@"gyroFlowPreferencesBookmarkData"];
    
    if (gyroFlowPreferencesBookmarkData == nil) {
        NSString *errorMessage = @"Failed to access Gyroflow's Preferences file.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    BOOL staleBookmark;
    NSURL *url = nil;
    NSError *bookmarkError = nil;
    url = [NSURL URLByResolvingBookmarkData:gyroFlowPreferencesBookmarkData
                                    options:NSURLBookmarkResolutionWithSecurityScope
                              relativeToURL:nil
                        bookmarkDataIsStale:&staleBookmark
                                      error:&bookmarkError];
    
    if (bookmarkError != nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to access Gyroflow's Preferences file due to a bookmark error:\n\n%@", bookmarkError.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    if (staleBookmark) {
        NSString *errorMessage = @"Failed to access Gyroflow's Preferences file due to a stale bookmark.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
            
    if (![url startAccessingSecurityScopedResource]) {
        NSString *errorMessage = @"Failed to start accessing the security scoped resource for Gyroflow's Preferences file.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfURL:url];
    
    [url stopAccessingSecurityScopedResource];
    
    if (![preferences isKindOfClass:[NSDictionary class]]) {
        NSString *errorMessage = @"Failed to read the Gyroflow's Preferences file.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    NSString *lastProjectPath = [preferences valueForKey:@"lastProject"];
    
    //---------------------------------------------------------
    // Make sure the last Gyroflow Project actually exists on
    // the file system:
    //---------------------------------------------------------
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (lastProjectPath && [fileManager fileExistsAtPath:lastProjectPath]) {
        NSURL *lastProjectURL = [NSURL fileURLWithPath:lastProjectPath];
        [self importGyroflowProjectWithOptionalURL:lastProjectURL completionHandler:nil];
    } else {
        [self showAlertWithMessage:@"No Gyroflow Project Found" info:@"The last Gyroflow Project loaded into Gyroflow no longer exists."];
    }
}

//---------------------------------------------------------
//
#pragma mark - Successful Import
//
//---------------------------------------------------------

//---------------------------------------------------------
// Show Successfully Imported Alert:
//---------------------------------------------------------
- (void)showSuccessfullyImportedAlert {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"suppressSuccessfullyImported"]) {
        NSAlert *alert                  = [GyroflowAlertFactory makeAlert];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Imported!";
        alert.informativeText           = @"The Gyroflow Project has been successfully imported into Final Cut Pro.\n\nYou can now adjust the parameters as required via the Video Inspector.";
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressSuccessfullyImported"];
            }
        }];
    }
}

//---------------------------------------------------------
//
#pragma mark - BRAW Toolbox Helpers
//
//---------------------------------------------------------

//---------------------------------------------------------
// Do we have access to the BRAW Toolbox Documents file?
//---------------------------------------------------------
-(BOOL)doWeHaveAccessToBRAWToolboxDocumentsFile {
    
    //---------------------------------------------------------
    // Check if we can read the BRAW Toolbox Documents file
    // already due to granting of sandbox access:
    //---------------------------------------------------------
    NSString *userHomePath = [self getUserHomeDirectoryPath];
    //NSLog(@"[Gyroflow Toolbox Renderer] userHomePath: %@", userHomePath);
    
    NSString *documentFilePath = [userHomePath stringByAppendingString:@"/Library/Group Containers/A5HDJTY9X5.com.latenitefilms.BRAWToolbox/Library/Application Support/BRAWToolbox.document"];
    //NSLog(@"[Gyroflow Toolbox Renderer] documentFilePath: %@", documentFilePath);
    
    NSURL *documentFileURL = [NSURL fileURLWithPath:documentFilePath];
    //NSLog(@"[Gyroflow Toolbox Renderer] documentFileURL: %@", documentFileURL);
        
    if ([[NSFileManager defaultManager] isReadableFileAtPath:[documentFileURL path]]) {
        return YES;
    }
    
    //---------------------------------------------------------
    // Read setting from User Defaults:
    //---------------------------------------------------------
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
    NSString *brawToolboxDocumentBookmarkData = [userDefaults stringForKey:@"brawToolboxDocumentBookmarkData"];
    
    //---------------------------------------------------------
    // Abort:
    //---------------------------------------------------------
    if (brawToolboxDocumentBookmarkData == nil || [brawToolboxDocumentBookmarkData isEqualToString:@""]) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Decode the Base64 bookmark data:
    //---------------------------------------------------------
    NSData *decodedBookmark = [[NSData alloc] initWithBase64EncodedString:brawToolboxDocumentBookmarkData
                                                                  options:0];

    //---------------------------------------------------------
    // Abort:
    //---------------------------------------------------------
    if (decodedBookmark == nil) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Resolve the decoded bookmark data into a
    // security-scoped URL:
    //---------------------------------------------------------
    NSError *bookmarkError  = nil;
    BOOL isStale            = NO;
    
    NSURL *urlToBRAWToolboxDocument = [NSURL URLByResolvingBookmarkData:decodedBookmark
                                                                options:NSURLBookmarkResolutionWithSecurityScope
                                                          relativeToURL:nil
                                                    bookmarkDataIsStale:&isStale
                                                                  error:&bookmarkError];
    
    //---------------------------------------------------------
    // Abort:
    //---------------------------------------------------------
    if (bookmarkError != nil) {
        return NO;
    }
    if (isStale) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Victory!
    //---------------------------------------------------------
    if ([urlToBRAWToolboxDocument startAccessingSecurityScopedResource]) {
        [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
        return YES;
    }
    
    //---------------------------------------------------------
    // Abort:
    //---------------------------------------------------------
    return NO;
}

//---------------------------------------------------------
// Request Access to BRAW Toolbox Documents File:
//---------------------------------------------------------
- (void)requestAccessToBRAWToolboxDocumentsFileWithCompletion:(BRAWCompletionHandler)completion {
    //---------------------------------------------------------
    // Show an alert:
    //---------------------------------------------------------
    NSAlert *alert          = [GyroflowAlertFactory makeAlert];
    alert.alertStyle        = NSAlertStyleInformational;
    alert.messageText       = @"Gyroflow Toolbox Requires Permission";
    alert.informativeText   = @"To make it easier to import BRAW Toolbox clips into Gyroflow Toolbox, you'll need to grant Gyroflow Toolbox sandbox access to a BRAW Toolbox helper file.\n\nOn the next panel, please select 'Grant Access' to continue.";
    [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result){

        //NSLog(@"[Gyroflow Toolbox Renderer] NSModalResponse result: %ld", (long)result);

        //---------------------------------------------------------
        // Attempt to get access to the BRAW Toolbox document:
        //---------------------------------------------------------
        NSString *userHomePath = [self getUserHomeDirectoryPath];
        //NSLog(@"[Gyroflow Toolbox Renderer] userHomePath: %@", userHomePath);
        
        NSString *documentFilePath = [userHomePath stringByAppendingString:@"/Library/Group Containers/A5HDJTY9X5.com.latenitefilms.BRAWToolbox/Library/Application Support/BRAWToolbox.document"];
        //NSLog(@"[Gyroflow Toolbox Renderer] documentFilePath: %@", documentFilePath);
        
        NSURL *documentFileURL = [NSURL fileURLWithPath:documentFilePath];
        //NSLog(@"[Gyroflow Toolbox Renderer] documentFileURL: %@", documentFileURL);
                    
        //---------------------------------------------------------
        // Limit the file type to a ".document":
        //---------------------------------------------------------
        UTType *documentType = [UTType typeWithFilenameExtension:@"document"];
        NSArray *allowedContentTypes = [NSArray arrayWithObjects:documentType, nil];
        
        //---------------------------------------------------------
        // Setup an NSOpenPanel:
        //---------------------------------------------------------
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        [panel setMessage:@"Please select the BRAW Toolbox.document file:"];
        [panel setPrompt:@"Grant Access"];
        [panel setCanChooseDirectories:NO];
        [panel setCanCreateDirectories:NO];
        [panel setCanChooseFiles:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setDirectoryURL:documentFileURL];
        [panel setAllowedContentTypes:allowedContentTypes];
        [panel setExtensionHidden:NO];
        [panel setCanSelectHiddenExtension:YES];
        [panel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
        
        [panel beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse openPanelResult){
            //---------------------------------------------------------
            // Abort if cancelled clicked:
            //---------------------------------------------------------
            if (openPanelResult != NSModalResponseOK) {
                return;
            }
            
            //---------------------------------------------------------
            // Get the open panel URL:
            //---------------------------------------------------------
            NSURL *openPanelURL = [panel URL];
            //NSLog(@"[Gyroflow Toolbox Renderer] openPanelURL: %@", [openPanelURL path]);
            
            //---------------------------------------------------------
            // Start accessing security scoped resource:
            //---------------------------------------------------------
            if (![openPanelURL startAccessingSecurityScopedResource]) {
                NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource when attempting to access the BRAW Toolbox document.\n\nThis shouldn't happen and is most likely a bug.";
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                return;
            } 
            //else {
                //NSLog(@"[Gyroflow Toolbox Renderer] We have sandbox access to: %@", [openPanelURL path]);
            //}
            
            //---------------------------------------------------------
            // Create a Security Scope Bookmark, so we can reload
            // later:
            //---------------------------------------------------------
            NSError *bookmarkError = nil;
            NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
            NSData *bookmark = [openPanelURL bookmarkDataWithOptions:bookmarkOptions
                                      includingResourceValuesForKeys:nil
                                                       relativeToURL:nil
                                                               error:&bookmarkError];
            
            //---------------------------------------------------------
            // There was an error creating the bookmark:
            //---------------------------------------------------------
            if (bookmarkError != nil) {
                NSString *errorMessage = [NSString stringWithFormat:@"Failed to create bookmark of the open panel file due to:\n\n%@", [bookmarkError localizedDescription]];
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                
                //---------------------------------------------------------
                // Stop Accessing Resource:
                //---------------------------------------------------------
                [openPanelURL stopAccessingSecurityScopedResource];
                return;
            }
            
            //---------------------------------------------------------
            // The bookmark is nil:
            //---------------------------------------------------------
            if (bookmark == nil) {
                NSString *errorMessage = @"Bookmark data from the open panel is nil.\n\nThis shouldn't happen and is most likely a bug.";
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                
                //---------------------------------------------------------
                // Stop Accessing Resource:
                //---------------------------------------------------------
                [openPanelURL stopAccessingSecurityScopedResource];
                return;
            }
            
            //---------------------------------------------------------
            // Same the encoded bookmark for next time:
            //---------------------------------------------------------
            NSString *base64EncodedBookmark = [bookmark base64EncodedStringWithOptions:0];
            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
            [userDefaults setObject:base64EncodedBookmark forKey:@"brawToolboxDocumentBookmarkData"];
            
            //---------------------------------------------------------
            // Stop Accessing Security Scoped Resources:
            //---------------------------------------------------------
            [openPanelURL stopAccessingSecurityScopedResource];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
        }];
    }];
}

//---------------------------------------------------------
//
#pragma mark - Import BRAW Toolbox
//
//---------------------------------------------------------

//---------------------------------------------------------
// Import BRAW Toolbox Clip with Path:
//---------------------------------------------------------
- (void)importBRAWToolboxClipWithPath:(NSString*)path bookmarkDataString:(NSString*)bookmarkDataString {

    //---------------------------------------------------------
    // If we need to request access to BRAW Toolbox document:
    //---------------------------------------------------------
    if (![self doWeHaveAccessToBRAWToolboxDocumentsFile]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] We need to request access to the BRAW Toolbox Document:");
        [self requestAccessToBRAWToolboxDocumentsFileWithCompletion:^{
            //---------------------------------------------------------
            // Try again:
            //---------------------------------------------------------
            [self importBRAWToolboxClipWithPath:path bookmarkDataString:bookmarkDataString];
        }];
        return;
    }
    
    //NSLog(@"[Gyroflow Toolbox Renderer] We have access to the BRAW Toolbox Document!");
        
    //---------------------------------------------------------
    // Check if we can read the BRAW Toolbox Documents file
    // already due to granting of sandbox access:
    //---------------------------------------------------------
    NSString *userHomePath = [self getUserHomeDirectoryPath];
    //NSLog(@"[Gyroflow Toolbox Renderer] userHomePath: %@", userHomePath);
    
    NSString *documentFilePath = [userHomePath stringByAppendingString:@"/Library/Group Containers/A5HDJTY9X5.com.latenitefilms.BRAWToolbox/Library/Application Support/BRAWToolbox.document"];
    //NSLog(@"[Gyroflow Toolbox Renderer] documentFilePath: %@", documentFilePath);
    
    NSURL *documentFileURL = [NSURL fileURLWithPath:documentFilePath];
    //NSLog(@"[Gyroflow Toolbox Renderer] documentFileURL: %@", documentFileURL);
            
    //---------------------------------------------------------
    // If we can already read the BRAW Toolbox Document file:
    //---------------------------------------------------------
    NSURL *urlToBRAWToolboxDocument = nil;
    if ([[NSFileManager defaultManager] isReadableFileAtPath:[documentFileURL path]]) {
        NSLog(@"[Gyroflow Toolbox Renderer] We can already read the BRAW Toolbox Documents file...");
        urlToBRAWToolboxDocument = documentFileURL;
    } else {
        //---------------------------------------------------------
        // Read setting from User Defaults:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
        NSString *brawToolboxDocumentBookmarkData = [userDefaults stringForKey:@"brawToolboxDocumentBookmarkData"];
        
        //---------------------------------------------------------
        // Make sure brawToolboxDocumentBookmarkData is valid:
        //---------------------------------------------------------
        if (brawToolboxDocumentBookmarkData == nil || [brawToolboxDocumentBookmarkData isEqualToString:@""]) {
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to get the BRAW Toolbox Document bookmark from Settings. This shouldn't be possible as we have already checked for access to it!"];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Decode the Base64 bookmark data:
        //---------------------------------------------------------
        NSData *decodedBookmark = [[NSData alloc] initWithBase64EncodedString:brawToolboxDocumentBookmarkData
                                                                      options:0];

        //---------------------------------------------------------
        // Make sure decodedBookmark is valid::
        //---------------------------------------------------------
        if (decodedBookmark == nil) {
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to decode the BRAW Toolbox Document bookmark. This shouldn't be possible as we have already checked for access to it!"];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Resolve the decoded bookmark data into a
        // security-scoped URL:
        //---------------------------------------------------------
        NSError *bookmarkError  = nil;
        BOOL isStale            = NO;
        
        urlToBRAWToolboxDocument = [NSURL URLByResolvingBookmarkData:decodedBookmark
                                                             options:NSURLBookmarkResolutionWithSecurityScope
                                                       relativeToURL:nil
                                                 bookmarkDataIsStale:&isStale
                                                               error:&bookmarkError];
        
        //---------------------------------------------------------
        // Was there a bookmark error?
        //---------------------------------------------------------
        if (bookmarkError != nil) {
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Failed resolve BRAW Toolbox Document bookmark due to: %@", bookmarkError.localizedDescription];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Is the bookmark stale?
        //---------------------------------------------------------
        if (isStale) {
            NSLog(@"[Gyroflow Toolbox Renderer] WARNING - The BRAW Toolbox Document Security Scoped Resource is stale. This shouldn't be possible as we have already checked for access to it!");
        }
        
        //---------------------------------------------------------
        // Start Access Security Scoped Resource:
        //---------------------------------------------------------
        if (![urlToBRAWToolboxDocument startAccessingSecurityScopedResource]) {
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to start accessing the BRAW Toolbox Document Security Scoped Resource. This shouldn't be possible as we have already checked for access to it!"];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
    }
    
    //---------------------------------------------------------
    // Resolve the decoded BRAW Toolbox bookmark data into a
    // security-scoped URL:
    //---------------------------------------------------------
    NSData *decodedBookmarkData = [[NSData alloc] initWithBase64EncodedString:bookmarkDataString
                                                                      options:0];
    
    NSError *brawBookmarkError  = nil;
    BOOL isStale                = NO;
    
    NSURL* brawDecodedBookmarkURL = [NSURL URLByResolvingBookmarkData:decodedBookmarkData
                                                              options:NSURLBookmarkResolutionWithSecurityScope
                                                        relativeToURL:urlToBRAWToolboxDocument
                                                  bookmarkDataIsStale:&isStale
                                                                error:&brawBookmarkError];
    
    //---------------------------------------------------------
    // If there was an error:
    //---------------------------------------------------------
    if (brawBookmarkError != nil) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [brawBookmarkError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                
        //---------------------------------------------------------
        // Stop Action API & Stop Accessing Resource:
        //---------------------------------------------------------
        [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
        return;
    }
    
    //---------------------------------------------------------
    // Failed to access resource due to sandbox:
    //---------------------------------------------------------
    if (![brawDecodedBookmarkURL startAccessingSecurityScopedResource]) {
        //---------------------------------------------------------
        // Show error message:
        //---------------------------------------------------------
        NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource when attempting to access the BRAW Toolbox clip.\n\nThis shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
        
        //---------------------------------------------------------
        // Stop Action API & Stop Accessing Resource:
        //---------------------------------------------------------
        [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
        return;
    }
        
    //NSLog(@"[Gyroflow Toolbox Renderer] We have access to the BRAW Clip: %@", [brawDecodedBookmarkURL path]);
    
    //---------------------------------------------------------
    // Check to see if there's a Gyroflow project next to the
    // BRAW file:
    //---------------------------------------------------------
    NSURL *gyroflowUrl = [[brawDecodedBookmarkURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
    NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
    
    //---------------------------------------------------------
    // It's a BRAW File, with a Gyroflow Project next to it
    //---------------------------------------------------------
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a BRAW File, with a Gyroflow Project next to it: %@", gyroflowUrl);
        [self importGyroflowProjectWithOptionalURL:gyroflowUrl completionHandler:^{
            //---------------------------------------------------------
            // Stop accessing resources:
            //---------------------------------------------------------
            //NSLog(@"[Gyroflow Toolbox Renderer] COMPLETION HANDLER TRIGGERED!");
            [brawDecodedBookmarkURL stopAccessingSecurityScopedResource];
            [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
        }];
        return;
    }
    
    //---------------------------------------------------------
    // It's a BRAW File, with no Gyroflow Project next to it:
    //---------------------------------------------------------
    //NSLog(@"[Gyroflow Toolbox Renderer] It's a BRAW File, with no Gyroflow Project next to it: %@", brawDecodedBookmarkURL);
    [self importMediaWithOptionalURL:brawDecodedBookmarkURL completionHandler:^{
        //---------------------------------------------------------
        // Stop accessing resources:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] COMPLETION HANDLER TRIGGERED!");
        [brawDecodedBookmarkURL stopAccessingSecurityScopedResource];
        [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
    }];
}

//---------------------------------------------------------
//
#pragma mark - Import Media & Gyroflow Project
//
//---------------------------------------------------------

//---------------------------------------------------------
// Import Gyroflow Project with Optional URL:
//---------------------------------------------------------
- (void)importGyroflowProjectWithOptionalURL:(NSURL*)optionalURL completionHandler:(BRAWCompletionHandler)completion {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] Import Gyroflow Project with Optional URL Triggered: %@", optionalURL);
    
    NSURL *openPanelURL = nil;
    BOOL isAccessible = NO;
    
    if (optionalURL) {
        isAccessible = [[NSFileManager defaultManager] isReadableFileAtPath:[optionalURL path]];
    }
    
    if (isAccessible) {
        //---------------------------------------------------------
        // The file is already accessible in the sandbox, so we
        // don't have to ask the user for permission:
        //---------------------------------------------------------
        openPanelURL = optionalURL;
    } else {
        //---------------------------------------------------------
        // Work out default URL for NSOpenPanel:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *desktopPath = [[self getUserHomeDirectoryPath] stringByAppendingString:@"/Desktop/"];
        NSURL *defaultFolderURL = [NSURL fileURLWithPath:desktopPath];
        if (optionalURL) {
            defaultFolderURL = optionalURL;
        } else {
            NSString *lastImportGyroflowProjectPath = [userDefaults stringForKey:@"lastImportGyroflowProjectPath"];
            if ([fileManager fileExistsAtPath:lastImportGyroflowProjectPath]) {
                defaultFolderURL = [NSURL fileURLWithPath:lastImportGyroflowProjectPath];
            }
        }
        
        //---------------------------------------------------------
        // Limit the file type to .gyroflow files:
        //---------------------------------------------------------
        UTType *gyroflowExtension       = [UTType typeWithFilenameExtension:@"gyroflow"];
        NSArray *allowedContentTypes    = [NSArray arrayWithObject:gyroflowExtension];
        
        //---------------------------------------------------------
        // Setup an NSOpenPanel:
        //---------------------------------------------------------
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        [panel setMessage:@"Please select a Gyroflow Project:"];
        [panel setPrompt:@"Open Gyroflow Project"];
        [panel setCanChooseDirectories:NO];
        [panel setCanCreateDirectories:YES];
        [panel setCanChooseFiles:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setDirectoryURL:defaultFolderURL];
        [panel setAllowedContentTypes:allowedContentTypes];
        [panel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
        
        //---------------------------------------------------------
        // Open the panel:
        //---------------------------------------------------------
        NSModalResponse result = [panel runModal];
        if (result != NSModalResponseOK) {
            return;
        }
        
        //---------------------------------------------------------
        // Save path for next time...
        //---------------------------------------------------------
        openPanelURL = [panel URL];
        [userDefaults setObject:[[openPanelURL path] stringByDeletingLastPathComponent] forKey:@"lastImportGyroflowProjectPath"];
        
        //---------------------------------------------------------
        // Start accessing security scoped resource:
        //---------------------------------------------------------
        BOOL startedOK = [openPanelURL startAccessingSecurityScopedResource];
        if (startedOK == NO) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
    }
    
    //---------------------------------------------------------
    // Show a Progress Alert:
    //---------------------------------------------------------
    NSProgressIndicator *progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 20.0f, 20.0f)];
    progressIndicator.style = NSProgressIndicatorStyleSpinning;
    [progressIndicator startAnimation:self];

    self.progressAlert = [GyroflowAlertFactory makeAlert];
    [self.progressAlert setMessageText:@"Processing Gyroflow Data"];
    [self.progressAlert setInformativeText:@"Please stand by while we prepare things for Final Cut Pro..."];
    [self.progressAlert setAlertStyle:NSAlertStyleInformational];
    [self.progressAlert setAccessoryView:progressIndicator];
    [self.progressAlert addButtonWithTitle:@"Cancel"];
    NSButton *button =  [[self.progressAlert buttons] objectAtIndex:0];
    [button setHidden:YES];
    [self.progressAlert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:nil];

    //---------------------------------------------------------
    // Give the Progress Alert 0.1 seconds to show:
    //---------------------------------------------------------
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        //---------------------------------------------------------
        // Trigger the main run loop to avoid any weirdness:
        //---------------------------------------------------------
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        
        //---------------------------------------------------------
        // Load the Custom Parameter Action API:
        //---------------------------------------------------------
        id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
        if (actionAPI == nil) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Create a Security Scope Bookmark, so we can reload
        // later:
        //---------------------------------------------------------
        NSError *bookmarkError = nil;
        NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
        NSData *bookmark = [openPanelURL bookmarkDataWithOptions:bookmarkOptions
                                  includingResourceValuesForKeys:nil
                                                   relativeToURL:nil
                                                           error:&bookmarkError];
        
        if (bookmarkError != nil) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            NSString *errorMessage = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        if (bookmark == nil) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            NSString *errorMessage = @"Bookmark data is nil. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        NSString *selectedGyroflowProjectFile            = [[openPanelURL lastPathComponent] stringByDeletingPathExtension];
        NSString *selectedGyroflowProjectPath            = [openPanelURL path];
        NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
        
        //---------------------------------------------------------
        // Read the Gyroflow Project Data from File:
        //---------------------------------------------------------
        NSError *readError = nil;
        NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:openPanelURL encoding:NSUTF8StringEncoding error:&readError];
        if (readError != nil) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            NSString *errorMessage = [NSString stringWithFormat:@"Failed to read Gyroflow Project File due to:\n\n%@", [readError localizedDescription]];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
        
        //---------------------------------------------------------
        // Make sure there's Gyro Data in the Gyroflow Project:
        //---------------------------------------------------------
        const char* hasData = doesGyroflowProjectContainStabilisationData([selectedGyroflowProjectData UTF8String]);
        NSString *hasDataResult = [NSString stringWithUTF8String: hasData];
        if (hasData) freeCString((char *)hasData);

        //NSLog(@"[Gyroflow Toolbox Renderer] hasDataResult: %@", hasDataResult);
        if (hasDataResult == nil || ![hasDataResult isEqualToString:@"YES"]) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            NSString *errorMessage = @"The Gyroflow file you imported doesn't seem to contain any gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including gyro data)' option.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"Gyro Data Not Found." info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        //---------------------------------------------------------
        // Get default values from the Gyroflow Project:
        //---------------------------------------------------------
        
        //---------------------------------------------------------
        // Use the Action API to allow us to change the parameters:
        //---------------------------------------------------------
        [actionAPI startAction:self];
        
        //---------------------------------------------------------
        // Load the Parameter Set API:
        //---------------------------------------------------------
        id<FxParameterSettingAPI_v5> paramSetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
        if (paramSetAPI == nil)
        {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            NSString *errorMessage = @"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        //---------------------------------------------------------
        // Generate a unique identifier:
        //---------------------------------------------------------
        NSUUID *uuid = [NSUUID UUID];
        NSString *uniqueIdentifier = uuid.UUIDString;
        [paramSetAPI setStringParameterValue:uniqueIdentifier toParameter:kCB_UniqueIdentifier];
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Path':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectPath toParameter:kCB_GyroflowProjectPath];
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Bookmark Data':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectBookmarkData toParameter:kCB_GyroflowProjectBookmarkData];
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Data':
        //---------------------------------------------------------
        NSData *gyroflowProjectData = [selectedGyroflowProjectData dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64EncodedString = [gyroflowProjectData base64EncodedStringWithOptions:0];
        [paramSetAPI setStringParameterValue:base64EncodedString toParameter:kCB_GyroflowProjectData];
        
        //---------------------------------------------------------
        // Update 'Loaded Gyroflow Project' Text Box:
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];
        
        //---------------------------------------------------------
        // Set parameters from Gyroflow Project file:
        //---------------------------------------------------------
        [self applyProjectDefaultsFromProject:selectedGyroflowProjectData parameterAPI:paramSetAPI];
        
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Stop accessing security scoped resource:
        //---------------------------------------------------------
        [openPanelURL stopAccessingSecurityScopedResource];
        
        //---------------------------------------------------------
        // Close the Progress Alert:
        //---------------------------------------------------------
        [NSApp endSheet:self.progressAlert.window];

        //---------------------------------------------------------
        // Show Victory Message:
        //---------------------------------------------------------
        [self showSuccessfullyImportedAlert];
        
        //---------------------------------------------------------
        // Trigger the Completion Handler:
        //---------------------------------------------------------
        if (completion) {
            completion();
        }
    });
}

//---------------------------------------------------------
// Import Media with Optional URL:
//---------------------------------------------------------
- (void)importMediaWithOptionalURL:(NSURL*)optionalURL completionHandler:(BRAWCompletionHandler)completion {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] FUNCTION: Import Media File with optional URL: %@", optionalURL);
    
    BOOL isAccessible = NO;
    
    if (optionalURL) {
        NSLog(@"[Gyroflow Toolbox Renderer] Checking if it's accessible..");
        isAccessible = [[NSFileManager defaultManager] isReadableFileAtPath:[optionalURL path]];
    }
    
    NSURL *panelURL = nil;
    if (!isAccessible) {
        //NSLog(@"[Gyroflow Toolbox Renderer] importMediaWithOptionalURL has an unaccessible NSURL, so we'll need to prompt for permission...");
        
        //---------------------------------------------------------
        // Work out default URL for NSOpenPanel:
        //---------------------------------------------------------
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *desktopPath = [[self getUserHomeDirectoryPath] stringByAppendingString:@"/Desktop/"];
        NSURL *defaultFolderURL = [NSURL fileURLWithPath:desktopPath];
        if (optionalURL) {
            defaultFolderURL = optionalURL;
        } else {
            NSString *lastImportMediaPath = [userDefaults stringForKey:@"lastImportMediaPath"];
            if ([fileManager fileExistsAtPath:lastImportMediaPath]) {
                defaultFolderURL = [NSURL fileURLWithPath:lastImportMediaPath];
            }
        }
        
        //---------------------------------------------------------
        // Limit the file type to Gyroflow supported media files:
        //---------------------------------------------------------
        UTType *mov                     = [UTType typeWithFilenameExtension:@"mov"];
        UTType *mxf                     = [UTType typeWithFilenameExtension:@"mxf"];
        UTType *braw                    = [UTType typeWithFilenameExtension:@"braw"];
        UTType *mpFour                  = [UTType typeWithFilenameExtension:@"mp4"];
        UTType *r3d                     = [UTType typeWithFilenameExtension:@"r3d"];
        UTType *insv                    = [UTType typeWithFilenameExtension:@"insv"];
                
        NSArray *allowedContentTypes    = [NSArray arrayWithObjects:mov, mxf, braw, mpFour, r3d, insv, nil];
        
        //---------------------------------------------------------
        // Setup an NSOpenPanel:
        //---------------------------------------------------------
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        [panel setCanChooseDirectories:NO];
        [panel setCanCreateDirectories:YES];
        [panel setCanChooseFiles:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setDirectoryURL:defaultFolderURL];
        [panel setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
        [panel setAllowedContentTypes:allowedContentTypes];
        
        //---------------------------------------------------------
        // Open the panel:
        //---------------------------------------------------------
        NSModalResponse result = [panel runModal];
        if (result != NSModalResponseOK) {
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            
            return;
        }
        
        //---------------------------------------------------------
        // Save path for next time...
        //---------------------------------------------------------
        panelURL = [panel URL];
        [userDefaults setObject:[[panelURL path] stringByDeletingLastPathComponent] forKey:@"lastImportMediaPath"];
        
        //---------------------------------------------------------
        // Start accessing security scoped resource:
        //---------------------------------------------------------
        if (![panelURL startAccessingSecurityScopedResource]) {
            //---------------------------------------------------------
            // Show an error message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        } else {
            NSLog(@"[Gyroflow Toolbox Renderer] Successfully started accessing security scoped resource!");
        }
    }

    //---------------------------------------------------------
    // Show a Progress Alert:
    //---------------------------------------------------------
    NSProgressIndicator *progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0.0f, 0.0f, 20.0f, 20.0f)];
    progressIndicator.style = NSProgressIndicatorStyleSpinning;
    [progressIndicator startAnimation:self];

    self.progressAlert = [GyroflowAlertFactory makeAlert];
    [self.progressAlert setMessageText:@"Processing Gyroflow Data"];
    [self.progressAlert setInformativeText:@"Please stand by while we prepare things for Final Cut Pro..."];
    [self.progressAlert setAlertStyle:NSAlertStyleInformational];
    [self.progressAlert setAccessoryView:progressIndicator];
    [self.progressAlert addButtonWithTitle:@"Cancel"];
    NSButton *button =  [[self.progressAlert buttons] objectAtIndex:0];
    [button setHidden:YES];
    [self.progressAlert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:nil];

    //---------------------------------------------------------
    // Give the Progress Alert 0.1 seconds to show:
    //---------------------------------------------------------
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        //---------------------------------------------------------
        // Trigger the main run loop to avoid any weirdness:
        //---------------------------------------------------------
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        
        NSURL *fileURL = nil;
                
        if (isAccessible) {
            //---------------------------------------------------------
            // The supplied optionalURL was already readable:
            //---------------------------------------------------------
            NSLog(@"[Gyroflow Toolbox Renderer] Using the optionalURL");
            fileURL = optionalURL;
        } else {
            //---------------------------------------------------------
            // We'll use the panel URL instead:
            //---------------------------------------------------------
            NSLog(@"[Gyroflow Toolbox Renderer] Using the panelURL");
            fileURL = panelURL;
        }

        //---------------------------------------------------------
        // Get the path from the URL:
        //---------------------------------------------------------
        NSString *path = [fileURL path];
        //NSLog(@"[Gyroflow Toolbox Renderer] Import Media File Path: %@", path);
                
        //---------------------------------------------------------
        // Use gyroflow_core to import the media file:
        //---------------------------------------------------------
        const char* importResult = importMediaFile(
                                                   [path UTF8String]        // const char*
                                                   );
        
        NSString *gyroflowProject = [NSString stringWithUTF8String: importResult];
        if (importResult) freeCString((char *)importResult);

        //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProject: %@", gyroflowProject);
            
        //---------------------------------------------------------
        // Abort if there's no valid Gyroflow Project:
        //---------------------------------------------------------
        if (gyroflowProject == nil || [gyroflowProject isEqualToString:@"FAIL"]) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            [self showAlertWithMessage:@"An error has occurred" info:@"Failed to generate a Gyroflow Project from the Media File.\n\nPlease check that the file you tried to import has gyroscope data."];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        //---------------------------------------------------------
        // Load the Custom Parameter Action API:
        //---------------------------------------------------------
        id<FxCustomParameterActionAPI_v4> actionAPI = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
        if (actionAPI == nil) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];
            
            [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen."];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        //---------------------------------------------------------
        // Just the filename (i.e. `A003_A002_1223KO_001`):
        //---------------------------------------------------------
        NSString *selectedGyroflowProjectFile = [[fileURL lastPathComponent] stringByDeletingPathExtension];
        
        //---------------------------------------------------------
        // The Gyroflow path, for example:
        // /Users/chrishocking/Desktop/Gyroflow Test Clips/- AdrianEddy - R3D/A003_A002_1223KO_001.gyroflow
        //---------------------------------------------------------
        NSString *selectedGyroflowProjectPath = [[[fileURL path] stringByDeletingPathExtension] stringByAppendingString:@".gyroflow"];
        
        //---------------------------------------------------------
        // No bookmark data, as the Gyroflow project doesn't
        // actually exist yet.
        //---------------------------------------------------------
        NSString *selectedGyroflowProjectBookmarkData = @"";
        
        //---------------------------------------------------------
        // Check to see if it has accurate timestamps:
        //---------------------------------------------------------
        BOOL requiresGyroflowLaunch = NO;
        //NSURL *savePanelURL = nil;
        
        const char* doesHaveAccurateTimestamps = hasAccurateTimestamps([gyroflowProject UTF8String]);
        NSString *doesHaveAccurateTimestampsString = [NSString stringWithUTF8String:doesHaveAccurateTimestamps];
        if (doesHaveAccurateTimestamps) freeCString((char *)doesHaveAccurateTimestamps);

        //NSLog(@"[Gyroflow Toolbox Renderer] doesHaveAccurateTimestamps: %@", doesHaveAccurateTimestampsString);
        
        if (![doesHaveAccurateTimestampsString isEqualToString:@"YES"] &&
            ![doesHaveAccurateTimestampsString isEqualToString:@"NO"]) {
            [NSApp endSheet:self.progressAlert.window];
            [self showAlertWithMessage:@"Unable to Read Motion Timing"
                info:@"Gyroflow could not read the timing metadata. Import the media again or choose a valid Gyroflow project."];
            if (completion) completion();
            return;
        }
        const char *motionStatus = doesGyroflowProjectContainStabilisationData(gyroflowProject.UTF8String);
        BOOL hasRecordedMotion = motionStatus && strcmp(motionStatus, "YES") == 0;
        if (motionStatus) freeCString((char *)motionStatus);
        if (hasRecordedMotion && [doesHaveAccurateTimestampsString isEqualToString:@"NO"]) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // The Gyroflow Project doesn't have accurate timestamps,
            // so we need to launch Gyroflow:
            //---------------------------------------------------------
            NSAlert *syncAlert = [GyroflowAlertFactory makeAlert];
            syncAlert.messageText = @"Synchronise Motion Data";
            syncAlert.informativeText = @"This clip does not provide accurate motion timestamps. After importing, use Motion Analysis → Synchronise Motion Data to align it in Final Cut Pro. You can also set an Additional Sync Offset in Advanced Stabilisation.";
            [syncAlert addButtonWithTitle:@"Continue in Final Cut Pro"];
            [syncAlert addButtonWithTitle:@"Open Gyroflow"];
            requiresGyroflowLaunch = [syncAlert runModal] == NSAlertSecondButtonReturn;
        }
        
        //---------------------------------------------------------
        // Create a new security-scoped bookmark:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] CREATING NEW SECURITY SCOPE BOOKMARK!");
        //NSLog(@"[Gyroflow Toolbox Renderer] fileURL: %@", fileURL);
        //NSLog(@"[Gyroflow Toolbox Renderer] fileURL: %@", [fileURL path]);
        
        /*
        BOOL canReadFile = [[NSFileManager defaultManager] isReadableFileAtPath:[fileURL path]];
        if (canReadFile) {
            NSLog(@"[Gyroflow Toolbox Renderer] CAN READ FILE: %@", [fileURL path]);
        } else {
            NSLog(@"[Gyroflow Toolbox Renderer] CANNOT READ FILE: %@", [fileURL path]);
        }
        */
        
        //---------------------------------------------------------
        // If the file wasn't already accessible, then we need to
        // startAccessingSecurityScopedResource:
        //---------------------------------------------------------
        if (!isAccessible) {
            if ([fileURL startAccessingSecurityScopedResource]) {
                NSLog(@"[Gyroflow Toolbox Renderer] startAccessingSecurityScopedResource for url!");
            } else {
                NSLog(@"[Gyroflow Toolbox Renderer] FAILED TO startAccessingSecurityScopedResource for url!");
            }
        } else {
            NSLog(@"[Gyroflow Toolbox Renderer] fileURL was already accessible, so no need to startAccessingSecurityScopedResource.");
        }
        
        NSError *bookmarkError = nil;
        NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
        NSData *bookmarkData = [fileURL bookmarkDataWithOptions:bookmarkOptions
                             includingResourceValuesForKeys:nil
                                              relativeToURL:nil
                                                      error:&bookmarkError];
        
        if (bookmarkError != nil) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];
            
            //---------------------------------------------------------
            // Show the error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Unable to create security-scoped bookmark in importMediaWithOptionalURL ('%@') due to: %@", fileURL, bookmarkError];
            //NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            //NSLog(@"[Gyroflow Toolbox Renderer] fileURL: %@", fileURL);
            //NSLog(@"[Gyroflow Toolbox Renderer] path: %@", path);
            [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        if (bookmarkData == nil) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // Show the error message:
            //---------------------------------------------------------
            NSString *errorMessage = [NSString stringWithFormat:@"Unable to create security-scoped bookmark in importMediaWithOptionalURL ('%@') due to: Bookmark is nil.", fileURL];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        NSString *mediaBookmarkData = [bookmarkData base64EncodedStringWithOptions:0];
            
        //---------------------------------------------------------
        // Get default values from the Gyroflow Project:
        //---------------------------------------------------------
                
        //---------------------------------------------------------
        // Use the Action API to allow us to change the parameters:
        //---------------------------------------------------------
        [actionAPI startAction:self];
        
        //---------------------------------------------------------
        // Load the Parameter Set API:
        //---------------------------------------------------------
        id<FxParameterSettingAPI_v5> paramSetAPI = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
        if (paramSetAPI == nil)
        {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // Show the Error Message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
        
        //---------------------------------------------------------
        // Update 'Media Path':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:path toParameter:kCB_MediaPath];
        //NSLog(@"[Gyroflow Toolbox Renderer] mediaPath: %@", path);
        
        //---------------------------------------------------------
        // Update 'Media Bookmark Data':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:mediaBookmarkData toParameter:kCB_MediaBookmarkData];
        //NSLog(@"[Gyroflow Toolbox Renderer] mediaBookmarkData: %@", mediaBookmarkData);
                
        //---------------------------------------------------------
        // Generate a unique identifier:
        //---------------------------------------------------------
        NSUUID *uuid = [NSUUID UUID];
        NSString *uniqueIdentifier = uuid.UUIDString;
        [paramSetAPI setStringParameterValue:uniqueIdentifier toParameter:kCB_UniqueIdentifier];
        //NSLog(@"[Gyroflow Toolbox Renderer] uniqueIdentifier: %@", uniqueIdentifier);
              
        //---------------------------------------------------------
        // Update 'Gyroflow Project Path':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectPath toParameter:kCB_GyroflowProjectPath];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectPath: %@", selectedGyroflowProjectPath);
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Bookmark Data':
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectBookmarkData toParameter:kCB_GyroflowProjectBookmarkData];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectBookmarkData: %@", selectedGyroflowProjectBookmarkData);
        
        //---------------------------------------------------------
        // Update 'Gyroflow Project Data':
        //---------------------------------------------------------
        NSData *gyroflowProjectData = [gyroflowProject dataUsingEncoding:NSUTF8StringEncoding];
        NSString *base64EncodedString = [gyroflowProjectData base64EncodedStringWithOptions:0];
        [paramSetAPI setStringParameterValue:base64EncodedString toParameter:kCB_GyroflowProjectData];
        
        //---------------------------------------------------------
        // Update 'Loaded Gyroflow Project' Text Box:
        //---------------------------------------------------------
        [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];
        //NSLog(@"[Gyroflow Toolbox Renderer] selectedGyroflowProjectFile: %@", selectedGyroflowProjectFile);
        
        //---------------------------------------------------------
        // Set parameters from Gyroflow Project file:
        //---------------------------------------------------------
        [self applyProjectDefaultsFromProject:gyroflowProject parameterAPI:paramSetAPI];
        
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        //---------------------------------------------------------
        // Stop accessing security scoped resource:
        //---------------------------------------------------------
        if (isAccessible) {
            //NSLog(@"[Gyroflow Toolbox Renderer] Stop accessing fileURL: %@", fileURL);
            [fileURL stopAccessingSecurityScopedResource];
        }
        
        //---------------------------------------------------------
        // If we need to Launch Gyroflow:
        //---------------------------------------------------------
        if (requiresGyroflowLaunch) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // This is depreciated, but there's no better way to do
            // it in a sandbox sadly:
            //---------------------------------------------------------
            #pragma GCC diagnostic push
            #pragma GCC diagnostic ignored "-Wdeprecated-declarations"
            [[NSWorkspace sharedWorkspace] openFile:[fileURL path] withApplication:@"Gyroflow"];
            #pragma GCC diagnostic pop
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
            
        //---------------------------------------------------------
        // Check to see if a lens profile is loaded in the
        // Gyroflow Project:
        //---------------------------------------------------------
        const char* lensProfileLoaded = isLensProfileLoaded([gyroflowProject UTF8String]);
        NSString *isLensProfileLoaded = [NSString stringWithUTF8String:lensProfileLoaded];
        if (lensProfileLoaded) freeCString((char *)lensProfileLoaded);

        //NSLog(@"[Gyroflow Toolbox Renderer] isLensProfileLoaded: %@", isLensProfileLoaded);
        if (isLensProfileLoaded == nil || ![isLensProfileLoaded isEqualToString:@"YES"]) {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // Show popup with instructions:
            //---------------------------------------------------------
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            if (![defaults boolForKey:@"suppressNoLensProfileDetected"]) {
                NSAlert *alert                  = [GyroflowAlertFactory makeAlert];
                alert.alertStyle                = NSAlertStyleInformational;
                alert.messageText               = @"No Lens Profile Detected";
                alert.informativeText           = @"Choose a lens profile for this camera and lens, or enter a 35 mm equivalent focal length in Lens Setup. A focal-length-only setup does not correct lens distortion.";
                alert.showsSuppressionButton    = YES;
                [alert addButtonWithTitle:@"Choose Lens Profile"];
                [alert addButtonWithTitle:@"Set Focal Length"];
                [alert beginSheetModalForWindow:NSApp.windows.firstObject completionHandler:^(NSModalResponse result) {
                    if ([alert suppressionButton].state == NSControlStateValueOn) {
                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressNoLensProfileDetected"];
                    }
                    
                    //---------------------------------------------------------
                    // Load Preset or Lens Profile:
                    //---------------------------------------------------------
                    if (result == NSAlertFirstButtonReturn) [self buttonLoadPresetLensProfileIsImporting:YES];
                    
                    //---------------------------------------------------------
                    // Trigger the Completion Handler:
                    //---------------------------------------------------------
                    if (completion) {
                        completion();
                    }
                    return;
                }];
            } else {
                //---------------------------------------------------------
                // Close the Progress Alert:
                //---------------------------------------------------------
                [NSApp endSheet:self.progressAlert.window];
            
                //---------------------------------------------------------
                // Load Preset or Lens Profile:
                //---------------------------------------------------------
                [self buttonLoadPresetLensProfileIsImporting:YES];
                
                //---------------------------------------------------------
                // Trigger the Completion Handler:
                //---------------------------------------------------------
                if (completion) {
                    completion();
                }
                return;
            }
        } else {
            //---------------------------------------------------------
            // Close the Progress Alert:
            //---------------------------------------------------------
            [NSApp endSheet:self.progressAlert.window];

            //---------------------------------------------------------
            // Show the success message:
            //---------------------------------------------------------
            [self showSuccessfullyImportedAlert];
            
            //---------------------------------------------------------
            // Trigger the Completion Handler:
            //---------------------------------------------------------
            if (completion) {
                completion();
            }
            return;
        }
    });
}

//---------------------------------------------------------
//
#pragma mark - Helpers
//
//---------------------------------------------------------

//------------------------------------------------------------------------------
// Helper to load a CGImageRef from the asset catalog:
//------------------------------------------------------------------------------
- (id)errorCGImageObjectForID:(NSString *)errorMessageID
{
    NSImage *img = [NSImage imageNamed:errorMessageID];
    if (!img) return nil;

    NSRect r = NSMakeRect(0, 0, img.size.width, img.size.height);
    CGImageRef cg = [img CGImageForProposedRect:&r context:nil hints:nil];
    if (!cg) return nil;

    return CFBridgingRelease(CGImageRetain(cg));
}

//---------------------------------------------------------
// Get Lens Profile Names from Directory:
//---------------------------------------------------------
- (NSDictionary *)newLensProfileIdentifiersFromDirectory:(NSString *)directoryPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray *jsonFilePaths = [NSMutableArray array];
    NSDictionary *result = [NSMutableDictionary dictionary];
    
    //---------------------------------------------------------
    // Enumerate all files in the directory and its
    // sub-directories:
    //---------------------------------------------------------
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:directoryPath]
                                          includingPropertiesForKeys:nil
                                                             options:0
                                                        errorHandler:nil];
    
    for (NSURL *fileURL in enumerator) {
        if ([[fileURL pathExtension] isEqualToString:@"json"]) {
            [jsonFilePaths addObject:fileURL.path];
        }
    }
    
    //---------------------------------------------------------
    // Read each JSON file and extract the "identifier":
    //---------------------------------------------------------
    for (NSString *filePath in jsonFilePaths) {
        NSData *data = [NSData dataWithContentsOfFile:filePath];
        if (data) {
            NSError *error = nil;
            NSDictionary *jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (error == nil && [jsonObject isKindOfClass:[NSDictionary class]] && jsonObject[@"identifier"]) {
                [(NSMutableDictionary *)result setObject:filePath forKey:jsonObject[@"identifier"]];
            }
        }
    }
    
    return result;
}

//---------------------------------------------------------
// Converts a NSNumber to a Control State:
//---------------------------------------------------------
- (NSInteger)boolToControlState:(BOOL)state {
    if (state) {
        return NSControlStateValueOn;
    } else {
        return NSControlStateValueOff;
    }
}

//---------------------------------------------------------
// Is Valid BRAW Toolbox String?
//---------------------------------------------------------
- (BOOL)isValidBRAWToolboxString:(NSString *)inputString {
    //---------------------------------------------------------
    // Check for <filter-video ref="XXX" name="BRAW Toolbox">:
    //---------------------------------------------------------
    NSRange filterVideoRange = [inputString rangeOfString:@"<filter-video ref=\"" options:NSCaseInsensitiveSearch];
    if (filterVideoRange.location == NSNotFound) {
        return NO;
    }
    NSRange brawToolboxRange = [inputString rangeOfString:@"name=\"BRAW Toolbox\">" options:NSCaseInsensitiveSearch];
    if (brawToolboxRange.location == NSNotFound) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Check for <param name="File Path":
    //---------------------------------------------------------
    NSRange filePathRange = [inputString rangeOfString:@"<param name=\"File Path\"" options:NSCaseInsensitiveSearch];
    if (filePathRange.location == NSNotFound) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Check for <param name="Bookmark Data":
    //---------------------------------------------------------
    NSRange bookmarkDataRange = [inputString rangeOfString:@"<param name=\"Bookmark Data\"" options:NSCaseInsensitiveSearch];
    if (bookmarkDataRange.location == NSNotFound) {
        return NO;
    }
    
    //---------------------------------------------------------
    // Check for <param name="Decode Quality":
    //---------------------------------------------------------
    NSRange decodeQualityRange = [inputString rangeOfString:@"<param name=\"Decode Quality\"" options:NSCaseInsensitiveSearch];
    if (decodeQualityRange.location == NSNotFound) {
        return NO;
    }
    
    //---------------------------------------------------------
    // If all checks passed:
    //---------------------------------------------------------
    return YES;
}

//---------------------------------------------------------
// Get user home directory path:
//---------------------------------------------------------
- (NSString*)getUserHomeDirectoryPath {
    
    NSString *homeDirectory = NSHomeDirectory();
    NSArray *pathComponents = [homeDirectory pathComponents];

    //---------------------------------------------------------
    // Find the index of "Users" in path components:
    //---------------------------------------------------------
    NSUInteger usersIndex = [pathComponents indexOfObject:@"Users"];

    //---------------------------------------------------------
    // If "Users" is found and the next component exists,
    // create the desired path and return it:
    //---------------------------------------------------------
    if (usersIndex != NSNotFound && usersIndex + 1 < [pathComponents count]) {
        NSString *username = pathComponents[usersIndex + 1];
        NSString *userHomePath = [NSString stringWithFormat:@"/Users/%@", username];
        NSLog(@"[Gyroflow Toolbox] getUserHomeDirectoryPath - Method 1: %@", userHomePath);
        return userHomePath;
    }

    //---------------------------------------------------------
    // If username not found, lets try the original method:
    //---------------------------------------------------------
    struct passwd *pw = getpwuid(getuid());
    assert(pw);
    NSString *userHomeDirectoryPath = [NSString stringWithUTF8String:pw->pw_dir];
    NSLog(@"[Gyroflow Toolbox] getUserHomeDirectoryPath - Method 2: %@", userHomeDirectoryPath);
    return userHomeDirectoryPath;
}

//---------------------------------------------------------
// Run on Main Queue Without Deadlocking:
//---------------------------------------------------------
void runOnMainQueueWithoutDeadlocking(void (^block)(void)) {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

//---------------------------------------------------------
// Get the NSURL of the Gyroflow Preferences file:
//---------------------------------------------------------
- (NSURL*)getGyroflowPreferencesFileURL {
    NSString *userHomeDirectoryPath = [self getUserHomeDirectoryPath];
    NSURL* userHomeDirectoryURL = [NSURL URLWithString:userHomeDirectoryPath];
    NSURL* gyroflowPlistURL = [userHomeDirectoryURL URLByAppendingPathComponent:@"/Library/Preferences/com.gyroflow-xyz.Gyroflow.plist"];
    return gyroflowPlistURL;
}

//---------------------------------------------------------
// Show Alert:
//---------------------------------------------------------
- (void)showAlertWithMessage:(NSString*)message info:(NSString*)info {
    runOnMainQueueWithoutDeadlocking(^{
        NSAlert *alert          = [GyroflowAlertFactory makeAlert];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = message;
        alert.informativeText   = info;
        alert.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        [alert runModal];
    });
}

//---------------------------------------------------------
// Show Asynchronous Alert:
//---------------------------------------------------------
- (void)showAsyncAlertWithMessage:(NSString*)message info:(NSString*)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert          = [GyroflowAlertFactory makeAlert];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = message;
        alert.informativeText   = info;
        alert.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        [alert runModal];
    });
}

// FxPlug calls these on its background analysis worker; no UI or rendering work is dispatched.
- (BOOL)desiredAnalysisTimeRange:(CMTimeRange *)desiredRange forInputWithTimeRange:(CMTimeRange)inputRange error:(NSError **)error {
    return [self.analysis desiredAnalysisTimeRange:desiredRange forInputWithTimeRange:inputRange error:error];
}
- (BOOL)setupAnalysisForTimeRange:(CMTimeRange)range frameDuration:(CMTime)duration error:(NSError **)error {
    return [self.analysis setupAnalysisForTimeRange:range frameDuration:duration error:error];
}
- (BOOL)analyzeFrame:(FxImageTile *)frame atTime:(CMTime)time error:(NSError **)error {
    return [self.analysis analyzeFrame:frame atTime:time error:error];
}
- (BOOL)cleanupAnalysis:(NSError **)error { return [self.analysis cleanupAnalysis:error]; }

@end
