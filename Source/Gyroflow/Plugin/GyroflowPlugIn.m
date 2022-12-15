//
//  GyroflowPlugIn.m
//  Gyroflow for Final Cut Pro
//
//  Created by Chris Hocking on 10/12/2022.
//

#import "GyroflowPlugIn.h"
#import <IOSurface/IOSurfaceObjC.h>
#import "TileableRemoteGyroflowShaderTypes.h"
#import "MetalDeviceCache.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import "GyroflowParameters.h"

#include "gyroflow.h"

//---------------------------------------------------------
// Plugin Parameter Constants:
//---------------------------------------------------------
enum {
    kCB_GyroflowFile    = 10,
    kCB_FOV             = 20,
    kCB_Smoothness      = 30,
    kCB_LensCorrection  = 40,
};

//---------------------------------------------------------
// Plugin Error Codes:
//
// All 3rd party error values should be >= 100000 if
// none of the above error enum values are sufficient.
//---------------------------------------------------------
enum {
    kFxError_failedToLoadTimingAPI = 100010,    // Failed to load FxTimingAPI_v4
    kFxError_failedToLoadParameterGetAPI,       // Failed to load FxParameterRetrievalAPI_v6
    kFxError_plugInStateIsNil                   // Plugin State is `nil`
};

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
                    kFxPropertyKey_IsThreadSafe                 : [NSNumber numberWithBool:YES],
                    kFxPropertyKey_MayRemapTime                 : [NSNumber numberWithBool:NO],
                    kFxPropertyKey_PixelTransformSupport        : [NSNumber numberWithInt:kFxPixelTransform_ScaleTranslate],
                    kFxPropertyKey_VariesWhenParamsAreStatic    : [NSNumber numberWithBool:NO]
                    };
    
    return YES;
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
            NSString* description = [NSString stringWithFormat:@"[Gyroflow] Unable to get the FxParameterCreationAPI_v5 in %s", __func__];
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedDescriptionKey : description }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: Gyroflow File
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Gyroflow File"
                                  parameterID:kCB_GyroflowFile
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow] Unable to add parameter: kCB_GyroflowFile"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: FOV
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow] Unable to add parameter: kCB_FOV"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: Smoothness
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow] Unable to add parameter: kCB_Smoothness"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }

    //---------------------------------------------------------
    // ADD PARAMETER: Lens Correction
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow] Unable to add parameter: kCB_LensCorrection"};
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
        NSLog(@"[Gyroflow] Unable to retrieve FxTimingAPI_v4 in pluginStateAtTime.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_failedToLoadTimingAPI
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
        NSLog(@"[Gyroflow] Unable to retrieve FxParameterRetrievalAPI_v6 in pluginStateAtTime.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_failedToLoadParameterGetAPI
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
        
    unsigned long long frame = ( (timelineTimeMinusStartTimeOfInputToFilterNumerator / timelineTimeMinusStartTimeOfInputToFilterDenominator) / ((Float64)timelineFrameDuration.value / (Float64)timelineFrameDuration.timescale) );

    NSNumber *frameToRender = [[[NSNumber alloc] initWithUnsignedLongLong:frame] autorelease];

    params.frameToRender = frameToRender;
    
    //---------------------------------------------------------
    // Frame Rate:
    //---------------------------------------------------------
    Float64 frameRate = [timingAPI timelineFpsNumeratorForEffect:self] / [timingAPI timelineFpsDenominatorForEffect:self];
    params.frameRate = [[[NSNumber alloc] initWithFloat:frameRate] autorelease];
    
    //---------------------------------------------------------
    // Gyroflow File:
    //---------------------------------------------------------
    NSString *gyroflowFile;
    [paramGetAPI getStringParameterValue:&gyroflowFile fromParameter:kCB_GyroflowFile];
    params.gyroflowFile = gyroflowFile;
    
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
            NSString* errorMessage = [NSString stringWithFormat:@"[Gyroflow] ERROR - Failed to create newPluginState due to '%@'", [newPluginStateError localizedDescription]];
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_plugInStateIsNil
                                     userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    
    *pluginState = newPluginState;
    
    if (*pluginState != nil) {
        succeeded = YES;
    } else {
        *error = [NSError errorWithDomain:FxPlugErrorDomain
                                     code:kFxError_plugInStateIsNil
                                 userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow] pluginState is nil in -pluginState." }];
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
                                        userInfo:@{NSLocalizedDescriptionKey : @"[Gyroflow] FATAL ERROR - No sourceImages in -destinationImageRect."}];
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
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow] FATAL ERROR - Invalid plugin state received from host." }];
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
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow] FATAL ERROR - Parameters was nil in -renderDestinationImage due to '%@'.", [paramsError localizedDescription]];
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
    NSNumber *frameToRender     = params.frameToRender;
    NSNumber *frameRate         = params.frameRate;
    NSString *gyroflowFile      = params.gyroflowFile;
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
    // Setup a new Command Queue:
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
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow] FATAL ERROR - Unable to get command queue. May need to increase cache size." }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Create a new Command Buffer:
    //---------------------------------------------------------
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    commandBuffer.label = @"GyroFlow Command Buffer";
    [commandBuffer enqueue];
    
    //---------------------------------------------------------
    // Setup our input texture:
    //---------------------------------------------------------
    id<MTLDevice> inputDevice       = [deviceCache deviceWithRegistryID:sourceImages[0].deviceRegistryID];
    id<MTLTexture> inputTexture     = [sourceImages[0] metalTextureForDevice:inputDevice];

    /*
    [Gyroflow] inputTexture.debugDescription: <AGXG13XFamilyTexture: 0x141f31800>
        label = <none>
        textureType = MTLTextureType2D
        pixelFormat = MTLPixelFormatRGBA16Float
        width = 1920
        height = 1080
        depth = 1
        arrayLength = 1
        mipmapLevelCount = 1
        sampleCount = 1
        cpuCacheMode = MTLCPUCacheModeDefaultCache
        storageMode = MTLStorageModeManaged
        hazardTrackingMode = MTLHazardTrackingModeTracked
        resourceOptions = MTLResourceCPUCacheModeDefaultCache MTLResourceStorageModeManaged MTLResourceHazardTrackingModeTracked
        usage = MTLTextureUsageShaderRead
        shareable = 0
        framebufferOnly = 0
        purgeableState = MTLPurgeableStateNonVolatile
        swizzle = [MTLTextureSwizzleRed, MTLTextureSwizzleGreen, MTLTextureSwizzleBlue, MTLTextureSwizzleAlpha]
        isCompressed = 0
        parentTexture = <null>
        parentRelativeLevel = 0
        parentRelativeSlice = 0
        buffer = <null>
        bufferOffset = 0
        bufferBytesPerRow = 0
        iosurface = 0x600000688c30
        iosurfacePlane = 0
        allowG<…>
    */
        
    // TODO: Having a MTLBuffer is probably unnecessary - but currently I'm just trying to get usable data from the MTLTexture.
    
    //---------------------------------------------------------
    // Create a new MTLBuffer to hold the copied data:
    //---------------------------------------------------------
    id<MTLBuffer> buffer = [inputDevice newBufferWithLength:inputTexture.width * inputTexture.height * 4 * 2
                                                    options:MTLResourceStorageModeShared];
    
    //---------------------------------------------------------
    // Copy the texture into the buffer:
    //---------------------------------------------------------
    MTLRegion region = MTLRegionMake2D(0, 0, inputTexture.width, inputTexture.height);
    [inputTexture getBytes:buffer.contents
               bytesPerRow:inputTexture.width * 4 * 2
             bytesPerImage:0
                fromRegion:region
               mipmapLevel:0
                     slice:0];
    
    NSLog(@"[Gyroflow] MTLBuffer: %@", buffer);
    /*
     [Gyroflow] MTLBuffer: <AGXG13XFamilyBuffer: 0x14100f580>
         label = <none>
         length = 33177600
         cpuCacheMode = MTLCPUCacheModeDefaultCache
         storageMode = MTLStorageModeShared
         hazardTrackingMode = MTLHazardTrackingModeTracked
         resourceOptions = MTLResourceCPUCacheModeDefaultCache MTLResourceStorageModeShared MTLResourceHazardTrackingModeTracked
         purgeableState = MTLPurgeableStateNonVolatile
     */
    
    //---------------------------------------------------------
    // Set the buffer sizes based on the MTLBuffer:
    //---------------------------------------------------------
    uint32_t sourceBufferSize = (uint32_t)buffer.length;
    uint32_t outputBufferSize = (uint32_t)buffer.length;
    
    //---------------------------------------------------------
    // Allocate a new buffers to hold the copied data:
    //---------------------------------------------------------
    unsigned char *sourceBuffer       = (unsigned char *)malloc(buffer.length);
    unsigned char *outputBuffer       = (unsigned char *)malloc(buffer.length);
    
    //---------------------------------------------------------
    // Copy the buffer's data into the new buffer:
    //---------------------------------------------------------
    memcpy((void *)sourceBuffer, buffer.contents, buffer.length);
    
    //NSLog(@"[Gyroflow] BEFORE sourceBuffer: %s", sourceBuffer);
    //NSLog(@"[Gyroflow] BEFORE sourceBufferSize: %u", sourceBufferSize);
    
    //---------------------------------------------------------
    // Collect all the Parameters for Gyroflow:
    //---------------------------------------------------------
    uint32_t        sourceWidth             = (uint32_t)inputTexture.width;
    uint32_t        sourceHeight            = (uint32_t)inputTexture.height;
    const char*     sourcePath              = [gyroflowFile UTF8String];
    int64_t         sourceTimestamp         = ([frameToRender floatValue] / [frameRate floatValue]) * 1000000.0;
    double          sourceFOV               = [fov doubleValue];
    double          sourceSmoothness        = [smoothness doubleValue];
    double          sourceLensCorrection    = [lensCorrection doubleValue];

    //---------------------------------------------------------
    // Trigger the Gyroflow Rust Function:
    //---------------------------------------------------------
    const char* result = processFrame(
                                      sourceWidth,              // uint32_t
                                      sourceHeight,             // uint32_t
                                      sourcePath,               // const char*
                                      sourceTimestamp,          // int64_t
                                      sourceFOV,                // double
                                      sourceSmoothness,         // double
                                      sourceLensCorrection,     // double
                                      sourceBuffer,             // unsigned char*
                                      sourceBufferSize,         // uint32_t
                                      outputBuffer,             // unsigned char*
                                      outputBufferSize          // uint32_t
                                      );
    
    //---------------------------------------------------------
    // Convert the result to a NSString:
    //---------------------------------------------------------
    NSString *resultString = [NSString stringWithUTF8String: result];
    NSLog(@"[Gyroflow] processFrame result: %@", resultString);
    
    //---------------------------------------------------------
    // If the result isn't "DONE" then abort:
    //---------------------------------------------------------
    /*
    if (![resultString isEqualToString:@"DONE"]) {
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow] Rust function failed with error: %@", resultString];
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
     */
    
    //---------------------------------------------------------
    // Replace the texture data:
    //---------------------------------------------------------
    if ([resultString isEqualToString:@"DONE"]) {
        /*
        NSString *debugMessage = [NSString stringWithFormat:@"[Gyroflow] RENDERING A FRAME:\n"];
        debugMessage = [debugMessage stringByAppendingFormat:@"sourceBuffer: %s\n", sourceBuffer];
        debugMessage = [debugMessage stringByAppendingFormat:@"sourceBufferSize: %u\n", sourceBufferSize];
        debugMessage = [debugMessage stringByAppendingFormat:@"outputBuffer: %s\n", outputBuffer];
        debugMessage = [debugMessage stringByAppendingFormat:@"outputBufferSize: %u\n", outputBufferSize];
        NSLog(@"%@", debugMessage);
        */
        // TODO: Remote this after testing...
        //memcpy(outputBuffer, sourceBuffer, sourceBufferSize);
        
        [inputTexture replaceRegion:region mipmapLevel:0 withBytes:outputBuffer bytesPerRow:inputTexture.width * 4 * 2];
    }
            
    //---------------------------------------------------------
    // Debugging:
    //---------------------------------------------------------
    /*
    NSString *debugMessage = [NSString stringWithFormat:@"[Gyroflow] RENDERING A FRAME:\n"];
    debugMessage = [debugMessage stringByAppendingFormat:@"inputTexture.width: %lu\n", (unsigned long)inputTexture.width];
    debugMessage = [debugMessage stringByAppendingFormat:@"inputTexture.height: %lu\n", (unsigned long)inputTexture.height];
    debugMessage = [debugMessage stringByAppendingFormat:@"frameToRender: %@\n", frameToRender];
    debugMessage = [debugMessage stringByAppendingFormat:@"frameRate: %@\n", frameRate];
    debugMessage = [debugMessage stringByAppendingFormat:@"timestamp: %lld\n", sourceTimestamp];
    debugMessage = [debugMessage stringByAppendingFormat:@"gyroflowFile: %@\n", gyroflowFile];
    debugMessage = [debugMessage stringByAppendingFormat:@"fov: %f\n", sourceFOV];
    debugMessage = [debugMessage stringByAppendingFormat:@"smoothness: %f\n", sourceSmoothness];
    debugMessage = [debugMessage stringByAppendingFormat:@"lensCorrection: %f\n", sourceLensCorrection];
    debugMessage = [debugMessage stringByAppendingFormat:@"outputWidth: %f\n", outputWidth];
    debugMessage = [debugMessage stringByAppendingFormat:@"outputHeight: %f\n", outputHeight];
    NSLog(@"%@", debugMessage);
    */
    
    //NSLog(@"[Gyroflow] inputTexture.debugDescription: %@", inputTexture.debugDescription);

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
    Vertex2D    vertices[]  = {
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
    id<MTLRenderPipelineState> pipelineState  = [deviceCache pipelineStateWithRegistryID:sourceImages[0].deviceRegistryID
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
    // haven’t already enqueued the command buffer with a call
    // to enqueue, calling this function also enqueues the
    // command buffer. The GPU executes the command buffer
    // after any command buffers enqueued before it on the same
    // command queue.
    //
    // You can only commit a command buffer once. You can’t
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
    
    return YES;
}

@end
