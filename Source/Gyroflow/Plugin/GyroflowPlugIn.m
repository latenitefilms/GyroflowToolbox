//
//  GyroflowPlugIn.m
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 10/12/2022.
//

//---------------------------------------------------------
// Import Headers:
//---------------------------------------------------------
#include "gyroflow.h"

#import "GyroflowPlugIn.h"
#import "GyroflowParameters.h"
#import "GyroflowConstants.h"

#import "LaunchGyroflowView.h"
#import "ImportGyroflowProjectView.h"
#import "ReloadGyroflowProjectView.h"

#import "TileableRemoteGyroflowShaderTypes.h"

#import "MetalDeviceCache.h"

#import <IOSurface/IOSurfaceObjC.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        _apiManager = newApiManager;
    }
    return self;
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
                    kFxPropertyKey_VariesWhenParamsAreStatic : [NSNumber numberWithBool:NO],
        
                    //---------------------------------------------------------
                    // @const      kFxPropertyKey_ChangesOutputSize
                    // @abstract   A key that determines whether your filter has the ability to change the size
                    //             of its output to be different than the size of its input.
                    // @discussion The value of this key is a Boolean NSNumber indicating whether your filter
                    //             returns an output that has a different size than the input. If not, return "NO"
                    //             and your filter's @c -destinationImageRect:sourceImages:pluginState:atTime:error:
                    //             method will not be called.
                    //---------------------------------------------------------
                    kFxPropertyKey_ChangesOutputSize : [NSNumber numberWithBool:NO],
        
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
                    kFxPropertyKey_DesiredProcessingColorInfo : [NSNumber numberWithInt:kFxImageColorInfo_RGB_LINEAR],
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
    if (parameterID == kCB_ImportGyroflowProject) {
        NSView* view = [[ImportGyroflowProjectView alloc] initWithFrame:NSMakeRect(0, 0, 135, 32) // x y w h
                                                       andAPIManager:_apiManager];
        //---------------------------------------------------------
        // It seems we need to cache the NSView, otherwise it gets
        // deallocated prematurely:
        //---------------------------------------------------------
        importGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_ReloadGyroflowProject) {
        NSView* view = [[ReloadGyroflowProjectView alloc] initWithFrame:NSMakeRect(0, 0, 135, 32) // x y w h
                                                          andAPIManager:_apiManager];
        //---------------------------------------------------------
        // It seems we need to cache the NSView, otherwise it gets
        // deallocated prematurely:
        //---------------------------------------------------------
        reloadGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_LaunchGyroflow) {
        NSView* view = [[LaunchGyroflowView alloc] initWithFrame:NSMakeRect(0, 0, 135, 32) // x y w h
                                                          andAPIManager:_apiManager];
        //---------------------------------------------------------
        // It seems we need to cache the NSView, otherwise it gets
        // deallocated prematurely:
        //---------------------------------------------------------
        launchGyroflowView = view;
        return view;
    } else {
        NSLog(@"[Gyroflow Toolbox] BUG - createViewForParameterID requested a parameterID that we haven't allowed for: %u", (unsigned int)parameterID);
        return nil;
    }
}

//---------------------------------------------------------
// Notifies your plug-in when it becomes part of user???s
// document.
//
// Called when a new plug-in instance is created or a
// document is loaded and an existing instance is
// deserialised. When the host calls this method, the
// plug-in is a part of the document and the various API
// objects work as expected.
//---------------------------------------------------------
- (void)pluginInstanceAddedToDocument
{
    NSLog(@"[Gyroflow Toolbox] pluginInstanceAddedToDocument!");
}

//---------------------------------------------------------
// addParametersWithError
//
// This method is where a plug-in defines its list of parameters.
//---------------------------------------------------------
- (BOOL)addParametersWithError:(NSError**)error
{
    //---------------------------------------------------------
    // Setup Parameter Creation API:
    //---------------------------------------------------------
    id<FxParameterCreationAPI_v5> paramAPI = [_apiManager apiForProtocol:@protocol(FxParameterCreationAPI_v5)];
    if (paramAPI == nil)
    {
        if (error != nil)
        {
            NSString* description = [NSString stringWithFormat:@"[Gyroflow Toolbox] Unable to get the FxParameterCreationAPI_v5 in %s", __func__];
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedDescriptionKey : description }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Launch Gyroflow' Button
    //---------------------------------------------------------
    if (![paramAPI addCustomParameterWithName:@"Launch Gyroflow"
                             parameterID:kCB_LaunchGyroflow
                            defaultValue:@0
                          parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_LaunchGyroflow"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Import Gyroflow Project' Button
    //---------------------------------------------------------
    if (![paramAPI addCustomParameterWithName:@"Import Gyroflow Project"
                             parameterID:kCB_ImportGyroflowProject
                            defaultValue:@0
                          parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_ImportGyroflowProject"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Loaded Gyroflow Project' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Loaded Gyroflow Project"
                                  parameterID:kCB_LoadedGyroflowProject
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_DISABLED | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_LoadedGyroflowProject"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Import Gyroflow Project' Button
    //---------------------------------------------------------
    if (![paramAPI addCustomParameterWithName:@"Reload Gyroflow Project"
                             parameterID:kCB_ReloadGyroflowProject
                            defaultValue:@0
                          parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_ReloadGyroflowProject"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Gyroflow Project Path' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Gyroflow Project Path"
                                  parameterID:kCB_GyroflowProjectPath
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_GyroflowProjectPath"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Gyroflow Project Bookmark Data' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Gyroflow Project Bookmark Data"
                                  parameterID:kCB_GyroflowProjectBookmarkData
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_GyroflowProjectBookmarkData"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Gyroflow Project Data' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Gyroflow Project Data"
                                  parameterID:kCB_GyroflowProjectData
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_GyroflowProjectData"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // START GROUP: 'Gyroflow Parameters'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"Gyroflow Parameters"
                              parameterID:kCB_GyroflowParameters
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_GyroflowParameters"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'FOV' Slider
    //---------------------------------------------------------
    if (![paramAPI addFloatSliderWithName:@"FOV"
                              parameterID:kCB_FOV
                             defaultValue:1.000
                             parameterMin:0.100
                             parameterMax:3.000
                                sliderMin:0.100
                                sliderMax:3.000
                                    delta:0.001
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_FOV"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Smoothness' Slider
    //---------------------------------------------------------
    if (![paramAPI addFloatSliderWithName:@"Smoothness"
                              parameterID:kCB_Smoothness
                             defaultValue:0.500
                             parameterMin:0.010
                             parameterMax:3.000
                                sliderMin:0.010
                                sliderMax:3.000
                                    delta:0.001
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_Smoothness"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }

    //---------------------------------------------------------
    // ADD PARAMETER: 'Lens Correction' Slider
    //---------------------------------------------------------
    if (![paramAPI addFloatSliderWithName:@"Lens Correction"
                              parameterID:kCB_LensCorrection
                             defaultValue:100.0
                             parameterMin:0.0
                             parameterMax:100.0
                                sliderMin:0.0
                                sliderMax:100.0
                                    delta:0.1
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add parameter: kCB_LensCorrection"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
        
    //---------------------------------------------------------
    // END GROUP: 'Gyroflow Parameters'
    //---------------------------------------------------------
    if (![paramAPI endParameterSubGroup])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] Unable to add end 'Gyroflow Parameters' Parameter"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    return YES;
}

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
    id<FxTimingAPI_v4> timingAPI = [_apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
    if (timingAPI == nil) {
        NSLog(@"[Gyroflow Toolbox] Unable to retrieve FxTimingAPI_v4 in pluginStateAtTime.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_FailedToLoadTimingAPI
                                     userInfo:@{
                                                NSLocalizedDescriptionKey :
                                                    @"Unable to retrieve FxTimingAPI_v4 in \
                                                    [-pluginStateAtTime:]" }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        NSLog(@"[Gyroflow Toolbox] Unable to retrieve FxParameterRetrievalAPI_v6 in pluginStateAtTime.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_FailedToLoadParameterGetAPI
                                     userInfo:@{
                                                NSLocalizedDescriptionKey :
                                                    @"Unable to retrieve FxParameterRetrievalAPI_v6 in \
                                                [-pluginStateAtTime:]" }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Create a new Parameters "holder":
    //---------------------------------------------------------
    GyroflowParameters *params = [[[GyroflowParameters alloc] init] autorelease];
    
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
    params.timestamp                = [[[NSNumber alloc] initWithFloat:timestamp] autorelease];
    
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
    params.gyroflowData = gyroflowData;
    
    //---------------------------------------------------------
    // FOV:
    //---------------------------------------------------------
    double fov;
    [paramGetAPI getFloatValue:&fov fromParameter:kCB_FOV atTime:renderTime];
    params.fov = [NSNumber numberWithDouble:fov];
    
    //---------------------------------------------------------
    // Smoothness:
    //---------------------------------------------------------
    double smoothness;
    [paramGetAPI getFloatValue:&smoothness fromParameter:kCB_Smoothness atTime:renderTime];
    params.smoothness = [NSNumber numberWithDouble:smoothness];
    
    //---------------------------------------------------------
    // Lens Correction:
    //---------------------------------------------------------
    double lensCorrection;
    [paramGetAPI getFloatValue:&lensCorrection fromParameter:kCB_LensCorrection atTime:renderTime];
    params.lensCorrection = [NSNumber numberWithDouble:lensCorrection];
    
    //---------------------------------------------------------
    // Write the parameters to the pluginState as `NSData`:
    //---------------------------------------------------------
    NSError *newPluginStateError;
    NSData *newPluginState = [NSKeyedArchiver archivedDataWithRootObject:params requiringSecureCoding:YES error:&newPluginStateError];
    if (newPluginState == nil) {
        if (error != NULL) {
            NSString* errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox] ERROR - Failed to create newPluginState due to '%@'", [newPluginStateError localizedDescription]];
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
        *error = [NSError errorWithDomain:FxPlugErrorDomain
                                     code:kFxError_PlugInStateIsNil
                                 userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] pluginState is nil in -pluginState." }];
        succeeded = NO;
    }
          
    return succeeded;
}

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
                                        userInfo:@{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] FATAL ERROR - No sourceImages in -destinationImageRect."}];
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
    if ((pluginState == nil) || (sourceImages [ 0 ].ioSurface == nil) || (destinationImage.ioSurface == nil))
    {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] FATAL ERROR - Invalid plugin state received from host." }];
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
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox] FATAL ERROR - Parameters was nil in -renderDestinationImage due to '%@'.", [paramsError localizedDescription]];
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }

    //---------------------------------------------------------
    // Get output width and height:
    //---------------------------------------------------------
    float outputWidth   = (float)(destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left);
    float outputHeight  = (float)(destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom);
    
    //---------------------------------------------------------
    // Get the parameter data:
    //---------------------------------------------------------
    NSNumber *timestamp         = params.timestamp;
    NSString *gyroflowPath      = params.gyroflowPath;
    NSString *gyroflowData      = params.gyroflowData;
    NSNumber *fov               = params.fov;
    NSNumber *smoothness        = params.smoothness;
    NSNumber *lensCorrection    = params.lensCorrection;
    
    //---------------------------------------------------------
    // Set up the renderer, in this case we are using Metal.
    //---------------------------------------------------------
    MetalDeviceCache* deviceCache = [MetalDeviceCache deviceCache];
    
    //---------------------------------------------------------
    // Setup the Pixel Format based on the destination image:
    //---------------------------------------------------------
    MTLPixelFormat pixelFormat = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
    
    //---------------------------------------------------------
    // Setup a new Command Queue for FxPlug4:
    //---------------------------------------------------------
    id<MTLCommandQueue> commandQueue = [deviceCache commandQueueWithRegistryID:sourceImages[0].deviceRegistryID
                                                                   pixelFormat:pixelFormat];

    //---------------------------------------------------------
    // If the Command Queue wasn't created, abort:
    //---------------------------------------------------------
    if (commandQueue == nil)
    {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox] FATAL ERROR - Unable to get command queue. May need to increase cache size." }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Setup our input texture:
    //---------------------------------------------------------
    id<MTLDevice> inputDevice       = [deviceCache deviceWithRegistryID:sourceImages[0].deviceRegistryID];
    id<MTLTexture> inputTexture     = [sourceImages[0] metalTextureForDevice:inputDevice];
    
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
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox] BUG - Unsupported pixelFormat for inputTexture: %lu", (unsigned long)inputTexture.pixelFormat];
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
    uint32_t        sourceWidth             = (uint32_t)inputTexture.width;
    uint32_t        sourceHeight            = (uint32_t)inputTexture.height;
    const char*     sourcePixelFormat       = [inputPixelFormat UTF8String];
    const char*     sourcePath              = [gyroflowPath UTF8String];
    const char*     sourceData              = [gyroflowData UTF8String];
    int64_t         sourceTimestamp         = [timestamp floatValue];
    double          sourceFOV               = [fov doubleValue];
    double          sourceSmoothness        = [smoothness doubleValue];
    double          sourceLensCorrection    = [lensCorrection doubleValue];
    
    //---------------------------------------------------------
    // Only trigger the Rust function if we have Gyroflow Data:
    //---------------------------------------------------------
    if (![gyroflowData isEqualToString:@""]) {
        //---------------------------------------------------------
        // Trigger the Gyroflow Rust Function:
        //---------------------------------------------------------
        const char* result = processFrame(
                              sourceWidth,              // uint32_t
                              sourceHeight,             // uint32_t
                              sourcePixelFormat,        // const char*
                              numberOfBytes,            // int
                              sourcePath,               // const char*
                              sourceData,               // const char*
                              sourceTimestamp,          // int64_t
                              sourceFOV,                // double
                              sourceSmoothness,         // double
                              sourceLensCorrection,     // double
                              inputTexture,             // MTLTexture
                              inputTexture,             // MTLTexture
                              commandQueue              // MTLCommandQueue
                              );
        
        NSString *resultString = [NSString stringWithUTF8String: result];
        //NSLog(@"[Gyroflow Toolbox] resultString: %@", resultString);
        
        if ([resultString isEqualToString:@"FAIL"]) {
            //---------------------------------------------------------
            // If we get a "FAIL" then abort:
            //---------------------------------------------------------
            NSString *errorMessage = @"[Gyroflow Toolbox] A fail message was received from the Rust function.";
            if (outError != NULL) {
                *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                                code:kFxError_InvalidParameter
                                            userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
            }
            return NO;
        }        
    }
  
    //---------------------------------------------------------
    // Debugging:
    //---------------------------------------------------------
    /*
    NSString *debugMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox] RENDERING A FRAME:\n"];
    debugMessage = [debugMessage stringByAppendingFormat:@"processFrame result: %@\n", resultString];
    debugMessage = [debugMessage stringByAppendingFormat:@"inputTexture.width: %lu\n", (unsigned long)inputTexture.width];
    debugMessage = [debugMessage stringByAppendingFormat:@"inputTexture.height: %lu\n", (unsigned long)inputTexture.height];
    debugMessage = [debugMessage stringByAppendingFormat:@"outputWidth: %f\n", outputWidth];
    debugMessage = [debugMessage stringByAppendingFormat:@"outputHeight: %f\n", outputHeight];
    debugMessage = [debugMessage stringByAppendingFormat:@"gyroflowPath: %@\n", gyroflowPath];
    debugMessage = [debugMessage stringByAppendingFormat:@"timestamp: %@\n", timestamp];
    debugMessage = [debugMessage stringByAppendingFormat:@"fov: %f\n", sourceFOV];
    debugMessage = [debugMessage stringByAppendingFormat:@"smoothness: %f\n", sourceSmoothness];
    debugMessage = [debugMessage stringByAppendingFormat:@"lensCorrection: %f\n", sourceLensCorrection];
    NSLog(@"%@", debugMessage);
    */
    
    //NSLog(@"[Gyroflow Toolbox] inputTexture.debugDescription: %@", inputTexture.debugDescription);

    //---------------------------------------------------------
    // Setup our output texture:
    //---------------------------------------------------------
    id<MTLTexture> outputTexture = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
    
    //---------------------------------------------------------
    // Setup our Color Attachment Descriptor.
    //
    // MTLRenderPassColorAttachmentDescriptor: A color render
    // target that serves as the output destination for color
    // pixels generated by a render pass.
    //---------------------------------------------------------
    MTLRenderPassColorAttachmentDescriptor* colorAttachmentDescriptor = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
    colorAttachmentDescriptor.texture = outputTexture;
    
    //---------------------------------------------------------
    // If the loadAction property of the attachment is set to
    // MTLLoadActionClear, then at the start of a render pass,
    // the GPU fills the texture with the value stored in the
    // clearColor property. Otherwise, the GPU ignores the
    // clearColor property.
    //
    // The clearColor property represents a set of RGBA
    // components. The default value is:
    //
    // (0.0, 0.0, 0.0, 1.0) (black).
    //
    // Use the MTLClearColorMake function to construct
    // a MTLClearColor value.
    //---------------------------------------------------------
    colorAttachmentDescriptor.clearColor = MTLClearColorMake(1.0, 0.5, 0.0, 1.0);
    
    //---------------------------------------------------------
    // Types of actions performed for an attachment at the
    // start of a rendering pass:
    //
    // * MTLLoadActionDontCare
    //   The GPU has permission to discard the existing
    //   contents of the attachment at the start of the
    //   render pass, replacing them with arbitrary data.
    //
    // * MTLLoadActionLoad
    //   The GPU preserves the existing contents of the
    //   attachment at the start of the render pass.
    //
    // * MTLLoadActionClear
    //   The GPU writes a value to every pixel in the
    //   attachment at the start of the render pass.
    //---------------------------------------------------------
    colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
    
    //---------------------------------------------------------
    // Setup our Render Pass Descriptor.
    //
    // MTLRenderPassDescriptor: A group of render targets that
    // hold the results of a render pass.
    //---------------------------------------------------------
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0] = colorAttachmentDescriptor;
    
    //---------------------------------------------------------
    // Create a new Command Buffer:
    //---------------------------------------------------------
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"GyroFlow Command Buffer";
    [commandBuffer enqueue];
    
    //---------------------------------------------------------
    // Setup our Command Encoder.
    //
    // renderCommandEncoderWithDescriptor: Creates an object
    // from a descriptor to encode a rendering pass into the
    // command buffer.
    //---------------------------------------------------------
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
    //---------------------------------------------------------
    // Calculate the vertex coordinates and the texture
    // coordinates:
    //---------------------------------------------------------
    Vertex2D vertices[] = {
        { {  outputWidth / 2.0, -outputHeight / 2.0 }, { 1.0, 1.0 } },
        { { -outputWidth / 2.0, -outputHeight / 2.0 }, { 0.0, 1.0 } },
        { {  outputWidth / 2.0,  outputHeight / 2.0 }, { 1.0, 0.0 } },
        { { -outputWidth / 2.0,  outputHeight / 2.0 }, { 0.0, 0.0 } }
    };
    
    //---------------------------------------------------------
    // Setup our viewport:
    //
    // MTLViewport: A 3D rectangular region for the viewport
    // clipping.
    //---------------------------------------------------------
    MTLViewport viewport = { 0, 0, outputWidth, outputHeight, -1.0, 1.0 };
    
    //---------------------------------------------------------
    // Sets the viewport used for transformations and clipping.
    //---------------------------------------------------------
    [commandEncoder setViewport:viewport];
    
    //---------------------------------------------------------
    // Setup our Render Pipeline State.
    //
    // MTLRenderPipelineState: An object that contains graphics
    // functions and configuration state to use in a render
    // command.
    //---------------------------------------------------------
    id<MTLRenderPipelineState> pipelineState = [deviceCache pipelineStateWithRegistryID:sourceImages[0].deviceRegistryID
                                                                            pixelFormat:pixelFormat];
    
    //---------------------------------------------------------
    // Sets the current render pipeline state object:
    //---------------------------------------------------------
    [commandEncoder setRenderPipelineState:pipelineState];
    
    //---------------------------------------------------------
    // Sets a block of data for the vertex shader:
    //---------------------------------------------------------
    [commandEncoder setVertexBytes:vertices
                            length:sizeof(vertices)
                           atIndex:BVI_Vertices];
    
    //---------------------------------------------------------
    // Set the viewport size:
    //---------------------------------------------------------
    simd_uint2  viewportSize = {
        (unsigned int)(outputWidth),
        (unsigned int)(outputHeight)
    };
    
    //---------------------------------------------------------
    // Sets a block of data for the vertex shader:
    //---------------------------------------------------------
    [commandEncoder setVertexBytes:&viewportSize
                            length:sizeof(viewportSize)
                           atIndex:BVI_ViewportSize];
    
    //---------------------------------------------------------
    // Sets a texture for the fragment function at an index
    // in the texture argument table:
    //---------------------------------------------------------
    [commandEncoder setFragmentTexture:inputTexture
                               atIndex:BTI_InputImage];
    
    //---------------------------------------------------------
    // drawPrimitives: Encodes a command to render one instance
    // of primitives using vertex data in contiguous array
    // elements.
    //
    // MTLPrimitiveTypeTriangleStrip: For every three adjacent
    // vertices, rasterize a triangle.
    //---------------------------------------------------------
    [commandEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                       vertexStart:0
                       vertexCount:4];
    
    //---------------------------------------------------------
    // Declares that all command generation from the encoder
    // is completed. After `endEncoding` is called, the
    // command encoder has no further use. You cannot encode
    // any other commands with this encoder.
    //---------------------------------------------------------
    [commandEncoder endEncoding];
    
    //---------------------------------------------------------
    // Commits the command buffer for execution.
    // After you call the commit method, the MTLDevice schedules
    // and executes the commands in the command buffer. If you
    // haven???t already enqueued the command buffer with a call
    // to enqueue, calling this function also enqueues the
    // command buffer. The GPU executes the command buffer
    // after any command buffers enqueued before it on the same
    // command queue.
    //
    // You can only commit a command buffer once. You can???t
    // commit a command buffer if the command buffer has an
    // active command encoder. Once you commit a command buffer,
    // you may not encode additional commands into it, nor can
    // you add a schedule or completion handler.
    //---------------------------------------------------------
    [commandBuffer commit];
    
    //---------------------------------------------------------
    // Blocks execution of the current thread until execution
    // of the command buffer is completed.
    //---------------------------------------------------------
    [commandBuffer waitUntilCompleted];
    
    //---------------------------------------------------------
    // Release the `colorAttachmentDescriptor` we created
    // earlier:
    //---------------------------------------------------------
    [colorAttachmentDescriptor release];
    
    //---------------------------------------------------------
    // Return the command queue back into the cache,
    // so we can re-use it again:
    //---------------------------------------------------------
    [deviceCache returnCommandQueueToCache:commandQueue];

    //---------------------------------------------------------
    // Release the Input Textures:
    //---------------------------------------------------------
    [inputTexture setPurgeableState:MTLPurgeableStateEmpty];
    
    return YES;
}

@end
