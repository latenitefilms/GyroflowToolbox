//
//  GyroflowPlugIn.m
//  Gyroflow Toolbox Renderer
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

#import "CustomButtonView.h"
#import "CustomDropZoneView.h"

#import "HeaderView.h"

#import "TileableRemoteBRAWShaderTypes.h"
#import "MetalDeviceCache.h"

#import <IOSurface/IOSurfaceObjC.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>
#include <sys/types.h>
#include <pwd.h>
#include <assert.h>

#include <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>

//---------------------------------------------------------
// Metal Performance Shaders for scaling:
//---------------------------------------------------------
#import <simd/simd.h>
#import <MetalKit/MetalKit.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

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
        //---------------------------------------------------------
        // Write log file to disk when using NSLog:
        //---------------------------------------------------------
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSString *applicationSupportDirectory = [paths firstObject];
        NSLog(@"applicationSupportDirectory: '%@'", applicationSupportDirectory);
        
        NSString* logPath = [applicationSupportDirectory stringByAppendingString:@"/FxPlug.log"];
        
        freopen([logPath fileSystemRepresentation],"a+",stderr);
        NSLog(@"[Gyroflow Toolbox Renderer] --------------------------------- START OF NEW SESSION ---------------------------------");
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        NSLog(@"[Gyroflow Toolbox Renderer] Version: %@ (%@)", version, build);
                
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
                    kFxPropertyKey_DesiredProcessingColorInfo : [NSNumber numberWithInt:kFxImageColorInfo_RGB_LINEAR],
                };
    return YES;
}

//---------------------------------------------------------
// createViewForParameterID
//
// Provides an NSView to be associated with the given
// parameter.
//
// NOTE: It seems we need to cache the NSView, otherwise it
// gets deallocated prematurely:
//---------------------------------------------------------
- (NSView*)createViewForParameterID:(UInt32)parameterID
{
    if (parameterID == kCB_ImportGyroflowProject) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_ImportGyroflowProject
                                                        buttonTitle:@"Import Gyroflow Project"];
        importGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_ImportMediaFile) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_ImportMediaFile
                                                        buttonTitle:@"Import Media File"];
        importMediaFileView = view;
        return view;
    } else if (parameterID == kCB_ReloadGyroflowProject) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_ReloadGyroflowProject
                                                        buttonTitle:@"Reload Gyroflow Project"];
        reloadGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_ExportGyroflowProject) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_ExportGyroflowProject
                                                        buttonTitle:@"Export Gyroflow Project"];
        exportGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_LaunchGyroflow) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_LaunchGyroflow
                                                        buttonTitle:@"Open in Gyroflow"];
        launchGyroflowView = view;
        return view;
    } else if (parameterID == kCB_LoadLastGyroflowProject) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_LoadLastGyroflowProject
                                                        buttonTitle:@"Import Last Gyroflow Project"];
        loadLastGyroflowProjectView = view;
        return view;
    } else if (parameterID == kCB_DropZone) {
        NSView* view = [[CustomDropZoneView alloc] initWithAPIManager:_apiManager
                                                         parentPlugin:self
                                                           buttonID:kCB_DropZone
                                                        buttonTitle:@"Import Dropped Clip"];
        dropZoneView = view;
        return view;
    } else if (parameterID == kCB_RevealInFinder) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_RevealInFinder
                                                        buttonTitle:@"Reveal in Finder"];
        revealInFinderView = view;
        return view;
    } else if (parameterID == kCB_LoadPresetLensProfile) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_LoadPresetLensProfile
                                                        buttonTitle:@"Load Preset/Lens Profile"];
        loadPresetLensProfileView = view;
        return view;
    } else if (parameterID == kCB_Header) {
        
        NSRect frameRect = NSMakeRect(0, 0, 200, 184); // x y w h
        NSView* view = [[HeaderView alloc] initWithFrame:frameRect];
        
        headerView = view;
        return view;
    } else if (parameterID == kCB_OpenUserGuide) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_OpenUserGuide
                                                        buttonTitle:@"Open User Guide"];
        launchGyroflowView = view;
        return view;
    } else {
        NSLog(@"[Gyroflow Toolbox Renderer] BUG - createViewForParameterID requested a parameterID that we haven't allowed for: %u", (unsigned int)parameterID);
        return nil;
    }
}

//---------------------------------------------------------
// Notifies your plug-in when it becomes part of user’s
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
    //NSLog(@"[Gyroflow Toolbox Renderer] pluginInstanceAddedToDocument!");
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
            NSString* description = [NSString stringWithFormat:@"[Gyroflow Toolbox Renderer] Unable to get the FxParameterCreationAPI_v5 in %s", __func__];
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_APIUnavailable
                                     userInfo:@{ NSLocalizedDescriptionKey : description }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    //
    // TOP SECTION:
    //
    //---------------------------------------------------------
    
    //---------------------------------------------------------
    // START GROUP: 'Top Section'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"Gyroflow Toolbox"
                              parameterID:kCB_TopSection
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_TopSection"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    } else {
        //---------------------------------------------------------
        // ADD PARAMETER: Header
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                      parameterID:kCB_Header
                                     defaultValue:@0
                                   parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_Header"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Open User Guide' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_OpenUserGuide
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_OpenUserGuide"};
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
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add end 'Top Section' Parameter"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
    
    //---------------------------------------------------------
    //
    // IMPORT SECTION:
    //
    //---------------------------------------------------------
    
    //---------------------------------------------------------
    // START GROUP: 'Import'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"Import"
                              parameterID:kCB_ImportSection
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ImportSection"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    } else {
        //---------------------------------------------------------
        // ADD PARAMETER: Drop Clip Here
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@"Drop Clip Here ➡"
                                 parameterID:kCB_DropZone
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_DropZone"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Import Gyroflow Project' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_ImportGyroflowProject
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ImportGyroflowProject"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Import Last Gyroflow Project' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_LoadLastGyroflowProject
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_LoadLastGyroflowProject"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Import Media File' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_ImportMediaFile
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ImportMediaFile"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Load Preset/Lens Profile' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_LoadPresetLensProfile
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_LoadPresetLensProfile"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // END GROUP: 'Import'
        //---------------------------------------------------------
        if (![paramAPI endParameterSubGroup])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add end 'Import Section' Parameter"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
    
    //---------------------------------------------------------
    //
    // GYROFLOW PARAMETERS:
    //
    //---------------------------------------------------------

    //---------------------------------------------------------
    // START GROUP: 'Gyroflow Parameters'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"Gyroflow Parameters"
                              parameterID:kCB_GyroflowParameters
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_GyroflowParameters"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    } else {
        //---------------------------------------------------------
        // ADD PARAMETER: 'FOV' Slider
        //
        // NOTE: 0.1 to 0.3 in Gyroflow OpenFX
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
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_FOV"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Smoothness' Slider
        //
        // NOTE: 0.01 to 3.00 in Gyroflow OpenFX
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
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_Smoothness"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }

        //---------------------------------------------------------
        // ADD PARAMETER: 'Lens Correction' Slider
        //
        // NOTE: In the Gyroflow user interface it shows 0 to 100,
        //       however internally it's actually 0 to 1.
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Lens Correction"
                                  parameterID:kCB_LensCorrection
                                 defaultValue:0.0
                                 parameterMin:0.0
                                 parameterMax:100.0
                                    sliderMin:0.0
                                    sliderMax:100.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_LensCorrection"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Horizon Lock' Slider
        //
        // NOTE: 0 to 100 in Gyroflow OpenFX
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Horizon Lock"
                                  parameterID:kCB_HorizonLock
                                 defaultValue:0.0
                                 parameterMin:0.0
                                 parameterMax:100.0
                                    sliderMin:0.0
                                    sliderMax:100.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_HorizonLock"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }

        //---------------------------------------------------------
        // ADD PARAMETER: 'Horizon Roll' Slider
        //
        // NOTE: -100 to 100 in Gyroflow OpenFX
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Horizon Roll"
                                  parameterID:kCB_HorizonRoll
                                 defaultValue:0.0
                                 parameterMin:-100.0
                                 parameterMax:100.0
                                    sliderMin:-100.0
                                    sliderMax:100.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_HorizonRoll"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Position Offset X' Slider
        //
        // NOTE: -100 to 100 in Gyroflow OpenFX
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Position Offset X"
                                  parameterID:kCB_PositionOffsetX
                                 defaultValue:0.0
                                 parameterMin:-100.0
                                 parameterMax:100.0
                                    sliderMin:-100.0
                                    sliderMax:100.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_PositionOffsetX"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Position Offset Y' Slider
        //
        // NOTE: -100 to 100 in Gyroflow OpenFX
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Position Offset Y"
                                  parameterID:kCB_PositionOffsetY
                                 defaultValue:0.0
                                 parameterMin:-100.0
                                 parameterMax:100.0
                                    sliderMin:-100.0
                                    sliderMax:100.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_PositionOffsetY"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Input Rotation' Slider
        //
        // Resolve UI:      -360 to 360
        // Gyroflow UI:     TBC
        // Internally:      TBC
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Input Rotation"
                                  parameterID:kCB_InputRotation
                                 defaultValue:0.0
                                 parameterMin:-360.0
                                 parameterMax:360.0
                                    sliderMin:-360.0
                                    sliderMax:360.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_InputRotation"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Video Rotation' Slider
        //
        // Resolve UI:      -360 to 360
        // Gyroflow UI:     TBC
        // Internally:      TBC
        //---------------------------------------------------------
        if (![paramAPI addFloatSliderWithName:@"Video Rotation"
                                  parameterID:kCB_VideoRotation
                                 defaultValue:0.0
                                 parameterMin:-360.0
                                 parameterMax:360.0
                                    sliderMin:-360.0
                                    sliderMax:360.0
                                        delta:0.1
                               parameterFlags:kFxParameterFlag_DEFAULT])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_VideoRotation"};
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
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add end 'Gyroflow Parameters' Parameter"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
    
    //---------------------------------------------------------
    //
    // TOOLS:
    //
    //---------------------------------------------------------
    
    //---------------------------------------------------------
    // START GROUP: 'Tools'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"Tools"
                              parameterID:kCB_ToolsSection
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ToolsSection"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    } else {
        //---------------------------------------------------------
        // ADD PARAMETER: 'Stabilisation Overview' Check Box
        //---------------------------------------------------------
        if (![paramAPI addToggleButtonWithName:@"Stabilisation Overview"
                                   parameterID:kCB_FieldOfViewOverview
                                  defaultValue:NO
                                parameterFlags:kFxParameterFlag_DEFAULT | kFxParameterFlag_NOT_ANIMATABLE]) {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_FieldOfViewOverview"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Disable Gyroflow Stretch' Check Box
        //---------------------------------------------------------
        if (![paramAPI addToggleButtonWithName:@"Disable Gyroflow Stretch"
                                   parameterID:kCB_DisableGyroflowStretch
                                  defaultValue:NO
                                parameterFlags:kFxParameterFlag_DEFAULT | kFxParameterFlag_NOT_ANIMATABLE]) {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_DisableGyroflowStretch"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // END GROUP: 'Tools'
        //---------------------------------------------------------
        if (![paramAPI endParameterSubGroup])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add end 'Tools' Parameter"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
        
    //---------------------------------------------------------
    //
    // FILE MANAGEMENT:
    //
    //---------------------------------------------------------
    
    //---------------------------------------------------------
    // START GROUP: 'File Management'
    //---------------------------------------------------------
    if (![paramAPI startParameterSubGroup:@"File Management"
                              parameterID:kCB_FileManagementSection
                           parameterFlags:kFxParameterFlag_DEFAULT])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_FileManagementSection"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    } else {
        //---------------------------------------------------------
        // ADD PARAMETER: 'Reload Gyroflow Project' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_ReloadGyroflowProject
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ReloadGyroflowProject"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Open in Gyroflow' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_LaunchGyroflow
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_LaunchGyroflow"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Export Gyroflow Project' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_ExportGyroflowProject
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_ExportGyroflowProject"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
        
        //---------------------------------------------------------
        // ADD PARAMETER: 'Reveal in Finder' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                 parameterID:kCB_RevealInFinder
                                defaultValue:@0
                              parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_RevealInFinder"};
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
                                     defaultValue:@"NOTHING LOADED"
                                   parameterFlags:kFxParameterFlag_DISABLED | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_LoadedGyroflowProject"};
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
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add end 'File Management' Parameter"};
                *error = [NSError errorWithDomain:FxPlugErrorDomain
                                             code:kFxError_InvalidParameter
                                         userInfo:userInfo];
            }
            return NO;
        }
    }
    
    //---------------------------------------------------------
    //
    // HIDDEN PARAMETERS:
    //
    //---------------------------------------------------------
    
    //---------------------------------------------------------
    // ADD PARAMETER: Unique Identifier
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Unique Identifier"
                                  parameterID:kCB_UniqueIdentifier
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_UniqueIdentifier"};
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_GyroflowProjectPath"};
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_GyroflowProjectBookmarkData"};
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
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_GyroflowProjectData"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    return YES;
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
    if (paramID == kCB_DisableGyroflowStretch) {
        NSLog(@"[Gyroflow Toolbox Renderer] Disable Gyroflow Stretch Changed!");
        trashCache();
    }
    return YES;
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
    id<FxTimingAPI_v4> timingAPI = [_apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
    if (timingAPI == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Unable to retrieve FxTimingAPI_v4 in pluginStateAtTime.");
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
        NSLog(@"[Gyroflow Toolbox Renderer] Unable to retrieve FxParameterRetrievalAPI_v6 in pluginStateAtTime.");
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
    // Horizon Lock:
    //---------------------------------------------------------
    double horizonLock;
    [paramGetAPI getFloatValue:&horizonLock fromParameter:kCB_HorizonLock atTime:renderTime];
    params.horizonLock = [NSNumber numberWithDouble:horizonLock];
    
    //---------------------------------------------------------
    // Horizon Roll:
    //---------------------------------------------------------
    double horizonRoll;
    [paramGetAPI getFloatValue:&horizonRoll fromParameter:kCB_HorizonRoll atTime:renderTime];
    params.horizonRoll = [NSNumber numberWithDouble:horizonRoll];

    //---------------------------------------------------------
    // Position Offset X:
    //---------------------------------------------------------
    double positionOffsetX;
    [paramGetAPI getFloatValue:&positionOffsetX fromParameter:kCB_PositionOffsetX atTime:renderTime];
    params.positionOffsetX = [NSNumber numberWithDouble:positionOffsetX];
    
    //---------------------------------------------------------
    // Position Offset Y:
    //---------------------------------------------------------
    double positionOffsetY;
    [paramGetAPI getFloatValue:&positionOffsetY fromParameter:kCB_PositionOffsetY atTime:renderTime];
    params.positionOffsetY = [NSNumber numberWithDouble:positionOffsetY];

    //---------------------------------------------------------
    // Input Rotation:
    //---------------------------------------------------------
    double inputRotation;
    [paramGetAPI getFloatValue:&inputRotation fromParameter:kCB_InputRotation atTime:renderTime];
    params.inputRotation = [NSNumber numberWithDouble:inputRotation];
    
    //---------------------------------------------------------
    // Video Rotation:
    //---------------------------------------------------------
    double videoRotation;
    [paramGetAPI getFloatValue:&videoRotation fromParameter:kCB_VideoRotation atTime:renderTime];
    params.videoRotation = [NSNumber numberWithDouble:videoRotation];
    
    //---------------------------------------------------------
    // FOV Overview:
    //---------------------------------------------------------
    BOOL fovOverview;
    [paramGetAPI getBoolValue:&fovOverview fromParameter:kCB_FieldOfViewOverview atTime:renderTime];
    params.fovOverview = [NSNumber numberWithBool:fovOverview];
    
    //---------------------------------------------------------
    // Disable Gyroflow Stretch:
    //---------------------------------------------------------
    BOOL disableGyroflowStretch;
    [paramGetAPI getBoolValue:&disableGyroflowStretch fromParameter:kCB_DisableGyroflowStretch atTime:renderTime];
    params.disableGyroflowStretch = [NSNumber numberWithBool:disableGyroflowStretch];
    
    //---------------------------------------------------------
    // Write the parameters to the pluginState as `NSData`:
    //---------------------------------------------------------
    NSError *newPluginStateError;
    NSData *newPluginState = [NSKeyedArchiver archivedDataWithRootObject:params requiringSecureCoding:YES error:&newPluginStateError];
    if (newPluginState == nil) {
        if (error != NULL) {
            NSString* errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox Renderer] ERROR - Failed to create newPluginState due to '%@'", [newPluginStateError localizedDescription]];
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
                                 userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] pluginState is nil in -pluginState." }];
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
    
    //NSLog(@"[Gyroflow Toolbox Renderer] Render time!");
    
    //---------------------------------------------------------
    // Make sure the plugin state is valid:
    //---------------------------------------------------------
    if ((pluginState == nil) || (sourceImages [ 0 ].ioSurface == nil) || (destinationImage.ioSurface == nil))
    {
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] FATAL ERROR - Invalid plugin state received from host." }];
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
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox Renderer] FATAL ERROR - Parameters was nil in -renderDestinationImage due to '%@'.", [paramsError localizedDescription]];
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
    
    //NSLog(@"[Gyroflow Toolbox Renderer] uniqueIdentifier: '%@'", uniqueIdentifier);
        
    //---------------------------------------------------------
    // Calculate output width & height:
    //---------------------------------------------------------
    float outputWidth       = (destinationImage.tilePixelBounds.right - destinationImage.tilePixelBounds.left);
    float outputHeight      = (destinationImage.tilePixelBounds.top - destinationImage.tilePixelBounds.bottom);
    float fullWidth         = (destinationImage.imagePixelBounds.right - destinationImage.imagePixelBounds.left);
    float fullHeight        = (destinationImage.imagePixelBounds.top - destinationImage.imagePixelBounds.bottom);
        
    //---------------------------------------------------------
    // Prepare our aspect ratio correction objects:
    //---------------------------------------------------------
    float correctedHeight               = outputHeight;
    float differenceBetweenHeights      = 0;
    
    //---------------------------------------------------------
    //
    // HOUSTON WE HAVE A PROBLEM!
    //
    // There's no unique identifier, so let's abort:
    //
    //---------------------------------------------------------
    if (uniqueIdentifier == nil || [uniqueIdentifier isEqualToString:@""]) {
        
        NSLog(@"[Gyroflow Toolbox Renderer] Showing early error message!");
        
        MetalDeviceCache* deviceCache       = [MetalDeviceCache deviceCache];
        MTLPixelFormat pixelFormat          = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
        id<MTLCommandQueue> commandQueue    = [deviceCache commandQueueWithRegistryID:destinationImage.deviceRegistryID
                                                                          pixelFormat:pixelFormat];
        if (commandQueue == nil)
        {
            NSString *errorMessage = @"[Gyroflow Toolbox Renderer] FATAL ERROR: commandQueue was nil when attempting to show an error message.";
            NSLog(@"%@", errorMessage);
            if (outError != NULL) {
                *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                                code:kFxError_CommandQueueWasNilDuringShowErrorMessage
                                            userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
            }
            return NO;
        }
        
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        commandBuffer.label = @"Gyroflow Toolbox Error Command Buffer";
        [commandBuffer enqueue];
                
        //---------------------------------------------------------
        // Load the texture from our "Assets":
        //---------------------------------------------------------
        MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:commandQueue.device];
        
        NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys:
                                 [NSNumber numberWithBool:YES], MTKTextureLoaderOptionSRGB,
                                 nil];
                
        id<MTLTexture> inputTexture         = [loader newTextureWithName:@"NoGyroflowProjectLoaded" scaleFactor:1.0 bundle:[NSBundle mainBundle] options:options error:nil];
        id<MTLTexture> outputTexture        = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
        
        //---------------------------------------------------------
        // If square pixels, we'll manipulate the height and y
        // axis manually:
        //---------------------------------------------------------
        if (fullHeight == outputHeight) {
            correctedHeight = ((float)inputTexture.height/(float)inputTexture.width) * outputWidth;
            differenceBetweenHeights = (outputHeight - correctedHeight) / 2;
        }
        
        //---------------------------------------------------------
        // Use a "Metal Performance Shader" to scale the texture
        // to the correct size. Note, we're using the full width
        // and height, to compensate for non-square pixels:
        //---------------------------------------------------------
        id<MTLTexture> scaledInputTexture = nil;
        if (fullHeight != outputHeight) {
            
            //---------------------------------------------------------
            // Create a new Command Buffer for scale transform:
            //---------------------------------------------------------
            id<MTLCommandBuffer> scaleCommandBuffer = [commandQueue commandBuffer];
            scaleCommandBuffer.label = @"Gyroflow Toolbox Scale Command Buffer";
            [scaleCommandBuffer enqueue];
            
            //---------------------------------------------------------
            // Create a new texture for the scaled image:
            //---------------------------------------------------------
            MTLTextureDescriptor *scaleTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:inputTexture.pixelFormat
                                                                                                              width:fullWidth
                                                                                                             height:fullHeight
                                                                                                          mipmapped:NO];
            
            scaledInputTexture = [inputTexture.device newTextureWithDescriptor:scaleTextureDescriptor];
            
            //---------------------------------------------------------
            // Work out how much to scale/re-position:
            //---------------------------------------------------------
            float scaleX        = (float)(fullWidth / inputTexture.width);
            float scaleY        = (float)(fullHeight / inputTexture.height);
                          
            if (scaleX > scaleY) {
                scaleX = scaleY;
            } else {
                scaleY = scaleX;
            }

            float translateX    = (float)((fullWidth - inputTexture.width * scaleX) / 2);
            float translateY    = (float)((fullHeight - inputTexture.height * scaleY) / 2);
                        
            MPSScaleTransform transform;
            transform.scaleX        = scaleX;         // The horizontal scale factor.
            transform.scaleY        = scaleY;         // The vertical scale factor.
            transform.translateX    = translateX;     // The horizontal translation factor.
            transform.translateY    = translateY;     // The vertical translation factor.

            //---------------------------------------------------------
            // A filter that resizes and changes the aspect ratio of
            // an image:
            //
            // NOTE: In v1.0.0 we use MPSImageLanczosScale, however
            //       I've changed to MPSImageBilinearScale as it's
            //       faster, and we probably prefer speed over
            //       quality for thumbnails.
            //---------------------------------------------------------
            MPSImageBilinearScale *filter = [[[MPSImageBilinearScale alloc] initWithDevice:commandQueue.device] autorelease];
            [filter setScaleTransform:&transform];
            [filter encodeToCommandBuffer:scaleCommandBuffer sourceTexture:inputTexture destinationTexture:scaledInputTexture];
            
            //---------------------------------------------------------
            // Commits the scale command buffer for execution:
            //---------------------------------------------------------
            [scaleCommandBuffer commit];
        }
        
        //---------------------------------------------------------
        // Release the texture loader:
        //---------------------------------------------------------
        [options release];
        [loader release];
        
        MTLRenderPassColorAttachmentDescriptor* colorAttachmentDescriptor   = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
        colorAttachmentDescriptor.texture = outputTexture;
        colorAttachmentDescriptor.clearColor = MTLClearColorMake(1.0, 0.5, 0.0, 1.0);
        colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
        MTLRenderPassDescriptor*    renderPassDescriptor    = [MTLRenderPassDescriptor renderPassDescriptor];
        renderPassDescriptor.colorAttachments [ 0 ] = colorAttachmentDescriptor;
        id<MTLRenderCommandEncoder>   commandEncoder  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        
        //---------------------------------------------------------
        // Calculate the vertex coordinates and the texture
        // coordinates:
        //---------------------------------------------------------
        float   textureLeft     = (destinationImage.tilePixelBounds.left - destinationImage.imagePixelBounds.left) / fullWidth;
        float   textureRight    = (destinationImage.tilePixelBounds.right - destinationImage.imagePixelBounds.left) / fullWidth;
        float   textureBottom   = (destinationImage.tilePixelBounds.bottom - destinationImage.imagePixelBounds.bottom) / fullHeight;
        float   textureTop      = (destinationImage.tilePixelBounds.top - destinationImage.imagePixelBounds.bottom) / fullHeight;
        
        Vertex2D    vertices[]  = {
            { {  outputWidth / 2.0f, -outputHeight / 2.0f }, { textureRight, textureTop } },
            { { -outputWidth / 2.0f, -outputHeight / 2.0f }, { textureLeft, textureTop } },
            { {  outputWidth / 2.0f,  outputHeight / 2.0f }, { textureRight, textureBottom } },
            { { -outputWidth / 2.0f,  outputHeight / 2.0f }, { textureLeft, textureBottom } }
        };
        
        //---------------------------------------------------------
        // Setup our viewport:
        //
        // MTLViewport: A 3D rectangular region for the viewport
        // clipping.
        //---------------------------------------------------------
        MTLViewport viewport = {
            0, differenceBetweenHeights, outputWidth, correctedHeight, -1.0, 1.0
        };
        
        //---------------------------------------------------------
        // Sets the viewport used for transformations and clipping:
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
        if (scaledInputTexture != nil) {
            //---------------------------------------------------------
            // Use our scaled input texture for non-square pixels:
            //---------------------------------------------------------
            [commandEncoder setFragmentTexture:scaledInputTexture
                                       atIndex:BTI_InputImage];
        } else {
            //---------------------------------------------------------
            // Use the data straight from the MTLBuffer for square
            // pixels to avoid any extra processing:
            //---------------------------------------------------------
            [commandEncoder setFragmentTexture:inputTexture
                                       atIndex:BTI_InputImage];
        }
        
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
        // Release the Input Texture:
        //---------------------------------------------------------
        if (inputTexture != nil) {
            [inputTexture setPurgeableState:MTLPurgeableStateEmpty];
            [inputTexture release];
            inputTexture = nil;
        }
        if (scaledInputTexture != nil) {
            [scaledInputTexture setPurgeableState:MTLPurgeableStateEmpty];
            [scaledInputTexture release];
            scaledInputTexture = nil;
        }
        
        //---------------------------------------------------------
        // Return the Command Queue back to the cache:
        //---------------------------------------------------------
        [deviceCache returnCommandQueueToCache:commandQueue];
        
        return YES;
    }
    
    //NSLog(@"[Gyroflow Toolbox Renderer] uniqueIdentifier during render: %@", uniqueIdentifier);
        
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
                                        userInfo:@{ NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] FATAL ERROR - Unable to get command queue. May need to increase cache size." }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Setup our input texture:
    //---------------------------------------------------------
    id<MTLDevice> inputDevice       = [deviceCache deviceWithRegistryID:sourceImages[0].deviceRegistryID];
    id<MTLTexture> inputTexture     = [sourceImages[0] metalTextureForDevice:inputDevice];
    
    //---------------------------------------------------------
    // Setup our output texture:
    //---------------------------------------------------------
    id<MTLTexture> outputTexture = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
    
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
        NSString *errorMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox Renderer] BUG - Unsupported pixelFormat for inputTexture: %lu", (unsigned long)inputTexture.pixelFormat];
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
    int64_t         xTimestamp                 = [timestamp floatValue];
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
    // Only trigger the Rust function if we have Gyroflow Data:
    //---------------------------------------------------------
    if (![gyroflowData isEqualToString:@""]) {
        //---------------------------------------------------------
        // Trigger the Gyroflow Rust Function:
        //---------------------------------------------------------
        const char* result = processFrame(
                              xUniqueIdentifier,        // const char*
                              xWidth,                   // uint32_t
                              xHeight,                  // uint32_t
                              xPixelFormat,             // const char*
                              numberOfBytes,            // int
                              xPath,                    // const char*
                              xData,                    // const char*
                              xTimestamp,               // int64_t
                              xFOV,                     // double
                              xSmoothness,              // double
                              xLensCorrection,          // double
                              xHorizonLock,             // double
                              xHorizonRoll,             // double
                              xPositionOffsetX,         // double
                              xPositionOffsetY,         // double
                              xInputRotation,           // double
                              xVideoRotation,           // double
                              xFOVOverview,             // uint8_t
                              xDisableGyroflowStretch,  // uint8_t
                              inputTexture,             // MTLTexture
                              outputTexture,            // MTLTexture
                              commandQueue              // MTLCommandQueue
                              );
        
        NSString *resultString = [NSString stringWithUTF8String: result];
        //NSLog(@"[Gyroflow Toolbox Renderer] resultString: %@", resultString);
        
        if ([resultString isEqualToString:@"FAIL"]) {
            
            NSLog(@"[Gyroflow Toolbox Renderer] Showing fail error message!");
            
            MetalDeviceCache* deviceCache       = [MetalDeviceCache deviceCache];
            MTLPixelFormat pixelFormat          = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
            id<MTLCommandQueue> commandQueue    = [deviceCache commandQueueWithRegistryID:destinationImage.deviceRegistryID
                                                                              pixelFormat:pixelFormat];
            if (commandQueue == nil)
            {
                NSString *errorMessage = @"[Gyroflow Toolbox Renderer] FATAL ERROR: commandQueue was nil when attempting to show an error message.";
                NSLog(@"%@", errorMessage);
                if (outError != NULL) {
                    *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                                    code:kFxError_CommandQueueWasNilDuringShowErrorMessage
                                                userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
                }
                return NO;
            }
            
            id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
            commandBuffer.label = @"Gyroflow Toolbox Error Command Buffer";
            [commandBuffer enqueue];
                    
            //---------------------------------------------------------
            // Load the texture from our "Assets":
            //---------------------------------------------------------
            MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:commandQueue.device];
            
            NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys:
                                     [NSNumber numberWithBool:YES], MTKTextureLoaderOptionSRGB,
                                     nil];
                    
            id<MTLTexture> inputTexture         = [loader newTextureWithName:@"GyroflowCoreRenderError" scaleFactor:1.0 bundle:[NSBundle mainBundle] options:options error:nil];
            id<MTLTexture> outputTexture        = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
            
            //---------------------------------------------------------
            // If square pixels, we'll manipulate the height and y
            // axis manually:
            //---------------------------------------------------------
            if (fullHeight == outputHeight) {
                correctedHeight = ((float)inputTexture.height/(float)inputTexture.width) * outputWidth;
                differenceBetweenHeights = (outputHeight - correctedHeight) / 2;
            }
            
            //---------------------------------------------------------
            // Use a "Metal Performance Shader" to scale the texture
            // to the correct size. Note, we're using the full width
            // and height, to compensate for non-square pixels:
            //---------------------------------------------------------
            id<MTLTexture> scaledInputTexture = nil;
            if (fullHeight != outputHeight) {
                
                //---------------------------------------------------------
                // Create a new Command Buffer for scale transform:
                //---------------------------------------------------------
                id<MTLCommandBuffer> scaleCommandBuffer = [commandQueue commandBuffer];
                scaleCommandBuffer.label = @"Gyroflow Toolbox Scale Command Buffer";
                [scaleCommandBuffer enqueue];
                
                //---------------------------------------------------------
                // Create a new texture for the scaled image:
                //---------------------------------------------------------
                MTLTextureDescriptor *scaleTextureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:inputTexture.pixelFormat
                                                                                                                  width:fullWidth
                                                                                                                 height:fullHeight
                                                                                                              mipmapped:NO];
                
                scaledInputTexture = [inputTexture.device newTextureWithDescriptor:scaleTextureDescriptor];
                
                //---------------------------------------------------------
                // Work out how much to scale/re-position:
                //---------------------------------------------------------
                float scaleX        = (float)(fullWidth / inputTexture.width);
                float scaleY        = (float)(fullHeight / inputTexture.height);
                              
                if (scaleX > scaleY) {
                    scaleX = scaleY;
                } else {
                    scaleY = scaleX;
                }

                float translateX    = (float)((fullWidth - inputTexture.width * scaleX) / 2);
                float translateY    = (float)((fullHeight - inputTexture.height * scaleY) / 2);
                            
                MPSScaleTransform transform;
                transform.scaleX        = scaleX;         // The horizontal scale factor.
                transform.scaleY        = scaleY;         // The vertical scale factor.
                transform.translateX    = translateX;     // The horizontal translation factor.
                transform.translateY    = translateY;     // The vertical translation factor.

                //---------------------------------------------------------
                // A filter that resizes and changes the aspect ratio of
                // an image:
                //
                // NOTE: In v1.0.0 we use MPSImageLanczosScale, however
                //       I've changed to MPSImageBilinearScale as it's
                //       faster, and we probably prefer speed over
                //       quality for thumbnails.
                //---------------------------------------------------------
                MPSImageBilinearScale *filter = [[[MPSImageBilinearScale alloc] initWithDevice:commandQueue.device] autorelease];
                [filter setScaleTransform:&transform];
                [filter encodeToCommandBuffer:scaleCommandBuffer sourceTexture:inputTexture destinationTexture:scaledInputTexture];
                
                //---------------------------------------------------------
                // Commits the scale command buffer for execution:
                //---------------------------------------------------------
                [scaleCommandBuffer commit];
            }
            
            //---------------------------------------------------------
            // Release the texture loader:
            //---------------------------------------------------------
            [options release];
            [loader release];
            
            MTLRenderPassColorAttachmentDescriptor* colorAttachmentDescriptor   = [[MTLRenderPassColorAttachmentDescriptor alloc] init];
            colorAttachmentDescriptor.texture = outputTexture;
            colorAttachmentDescriptor.clearColor = MTLClearColorMake(1.0, 0.5, 0.0, 1.0);
            colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
            MTLRenderPassDescriptor*    renderPassDescriptor    = [MTLRenderPassDescriptor renderPassDescriptor];
            renderPassDescriptor.colorAttachments [ 0 ] = colorAttachmentDescriptor;
            id<MTLRenderCommandEncoder>   commandEncoder  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            
            //---------------------------------------------------------
            // Calculate the vertex coordinates and the texture
            // coordinates:
            //---------------------------------------------------------
            float   textureLeft     = (destinationImage.tilePixelBounds.left - destinationImage.imagePixelBounds.left) / fullWidth;
            float   textureRight    = (destinationImage.tilePixelBounds.right - destinationImage.imagePixelBounds.left) / fullWidth;
            float   textureBottom   = (destinationImage.tilePixelBounds.bottom - destinationImage.imagePixelBounds.bottom) / fullHeight;
            float   textureTop      = (destinationImage.tilePixelBounds.top - destinationImage.imagePixelBounds.bottom) / fullHeight;
            
            Vertex2D    vertices[]  = {
                { {  outputWidth / 2.0f, -outputHeight / 2.0f }, { textureRight, textureTop } },
                { { -outputWidth / 2.0f, -outputHeight / 2.0f }, { textureLeft, textureTop } },
                { {  outputWidth / 2.0f,  outputHeight / 2.0f }, { textureRight, textureBottom } },
                { { -outputWidth / 2.0f,  outputHeight / 2.0f }, { textureLeft, textureBottom } }
            };
            
            //---------------------------------------------------------
            // Setup our viewport:
            //
            // MTLViewport: A 3D rectangular region for the viewport
            // clipping.
            //---------------------------------------------------------
            MTLViewport viewport = {
                0, differenceBetweenHeights, outputWidth, correctedHeight, -1.0, 1.0
            };
            
            //---------------------------------------------------------
            // Sets the viewport used for transformations and clipping:
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
            if (scaledInputTexture != nil) {
                //---------------------------------------------------------
                // Use our scaled input texture for non-square pixels:
                //---------------------------------------------------------
                [commandEncoder setFragmentTexture:scaledInputTexture
                                           atIndex:BTI_InputImage];
            } else {
                //---------------------------------------------------------
                // Use the data straight from the MTLBuffer for square
                // pixels to avoid any extra processing:
                //---------------------------------------------------------
                [commandEncoder setFragmentTexture:inputTexture
                                           atIndex:BTI_InputImage];
            }
            
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
            // Release the Input Texture:
            //---------------------------------------------------------
            if (inputTexture != nil) {
                [inputTexture setPurgeableState:MTLPurgeableStateEmpty];
                [inputTexture release];
                inputTexture = nil;
            }
            if (scaledInputTexture != nil) {
                [scaledInputTexture setPurgeableState:MTLPurgeableStateEmpty];
                [scaledInputTexture release];
                scaledInputTexture = nil;
            }
            
            //---------------------------------------------------------
            // Return the Command Queue back to the cache:
            //---------------------------------------------------------
            [deviceCache returnCommandQueueToCache:commandQueue];
            
            return YES;
            
        }        
    }
  
    //---------------------------------------------------------
    // Debugging:
    //---------------------------------------------------------
    /*
    NSString *debugMessage = [NSString stringWithFormat:@"[Gyroflow Toolbox Renderer] RENDERING A FRAME:\n"];
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
    
    //NSLog(@"[Gyroflow Toolbox Renderer] inputTexture.debugDescription: %@", inputTexture.debugDescription);
    
    //---------------------------------------------------------
    // Return the command queue back into the cache,
    // so we can re-use it again:
    //---------------------------------------------------------
    [deviceCache returnCommandQueueToCache:commandQueue];

    //---------------------------------------------------------
    // Release the Input Textures:
    //---------------------------------------------------------
    //[inputTexture setPurgeableState:MTLPurgeableStateEmpty];
    
    return YES;
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
        [self buttonLoadPresetLensProfile];
    } else if (buttonID == kCB_OpenUserGuide) {
        [self buttonOpenUserGuide];
    }
}

//---------------------------------------------------------
// BUTTON: 'Export Gyroflow Project'
//---------------------------------------------------------
- (void)buttonExportGyroflowProject {
    [self showAlertWithMessage:@"Export!" info:@"Coming soon!"];
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
- (void)buttonLoadPresetLensProfile {
    
    //---------------------------------------------------------
    // Get the Lens Profiles path:
    //---------------------------------------------------------
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *lensProfilesPath = [mainBundle pathForResource:@"Lens Profiles" ofType:nil inDirectory:nil];
    NSURL *lensProfilesURL = [NSURL fileURLWithPath:lensProfilesPath];
    
    //---------------------------------------------------------
    // Setup an NSOpenPanel:
    //---------------------------------------------------------
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setCanCreateDirectories:YES];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setDirectoryURL:lensProfilesURL];
    
    //---------------------------------------------------------
    // Limit the file type to Gyroflow supported media files:
    //---------------------------------------------------------
    UTType *gyroflow                 = [UTType typeWithFilenameExtension:@"gyroflow"];
    UTType *json                     = [UTType typeWithFilenameExtension:@"json"];
    
    NSArray *allowedContentTypes    = [NSArray arrayWithObjects:gyroflow, json, nil];
    [panel setAllowedContentTypes:allowedContentTypes];
    
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
        [self showAlertWithMessage:@"An error has occurred." info:@"Failed to startAccessingSecurityScopedResource. This shouldn't happen."];
        return;
    }
    
    /*
     const char* loadLensProfile(
         const char*                 gyroflow_project_data,
         const char*                 lens_profile_path
     );

     */
    
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug."];
        return;
    }
        
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil)
    {
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
    
    if (gyroflowProjectData == nil) {
        [self showAlertWithMessage:@"Failed to get Gyroflow Project" info:@"Please ensure you have a Gyroflow Project already loaded."];
        return;
    }
        
    NSString *lensProfilePath = [url path];
    
    const char* loadResult = loadLensProfile(
                                             [gyroflowProjectData UTF8String],
                                             [lensProfilePath UTF8String]
                                             );
    
    [url stopAccessingSecurityScopedResource];
    
    NSString *loadResultString = [NSString stringWithUTF8String: loadResult];
    
    if (loadResultString == nil || [loadResultString isEqualToString:@"FAIL"]) {
        [self showAlertWithMessage:@"An error has occurred" info:@"Failed to load a Lens Profile or Preset."];
        [actionAPI endAction:self];
        return;
    }
    
    [paramSetAPI setStringParameterValue:loadResultString toParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Trash the cache!
    //---------------------------------------------------------
    trashCache();
    
    [self showAlertWithMessage:@"VICTORY!" info:@""];
    
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
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug."];
        return;
    }
        
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
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
    [self importMediaWithOptionalURL:nil];
}

//---------------------------------------------------------
// BUTTON: 'Launch Gyroflow'
//---------------------------------------------------------
- (void)buttonLaunchGyroflow {
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug."];
        return;
    }
        
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }
    
    //---------------------------------------------------------
    // Get the existing Gyroflow project path:
    //---------------------------------------------------------
    NSString *existingProjectPath = nil;
    [paramGetAPI getStringParameterValue:&existingProjectPath fromParameter:kCB_GyroflowProjectPath];
    
    NSURL *existingProjectURL = [NSURL fileURLWithPath:existingProjectPath];
            
    //---------------------------------------------------------
    // Open Gyroflow or the current Gyroflow Project:
    //---------------------------------------------------------
    NSString *bundleIdentifier = @"xyz.gyroflow";
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
    
    if (appURL == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Could not find Gyroflow Installation");
        [actionAPI endAction:self];
        [self showAlertWithMessage:@"Failed to launch Gyroflow." info:@"Please check that Gyroflow is installed and try again."];
        return;
    }
    
    if (existingProjectPath == nil || [existingProjectPath isEqualToString:@""] || existingProjectURL == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Could not find existing project.");
        [[NSWorkspace sharedWorkspace] openURL:appURL];
    } else {
       //---------------------------------------------------------
       // Get the encoded bookmark string:
       //---------------------------------------------------------
       NSString *encodedBookmark;
       [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_GyroflowProjectBookmarkData];
       
       //---------------------------------------------------------
       // Make sure there's actually encoded bookmark data:
       //---------------------------------------------------------
       if ([encodedBookmark isEqualToString:@""]) {
           NSLog(@"[Gyroflow Toolbox Renderer] Encoded Bookmark is empty.");
           [[NSWorkspace sharedWorkspace] openURL:appURL];
           [actionAPI endAction:self];
           return;
       }
       
       //---------------------------------------------------------
       // Decode the Base64 bookmark data:
       //---------------------------------------------------------
       NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                                 options:0] autorelease];

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
           NSLog(@"[Gyroflow Toolbox Renderer] Bookmark error: %@", bookmarkError.localizedDescription);
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
        // There is an existing project path, so load Gyroflow
        // with that path:
        //---------------------------------------------------------
        //NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleIdentifier];
        //NSWorkspaceOpenConfiguration *config = [[[NSWorkspaceOpenConfiguration alloc] init] autorelease];
        //[[NSWorkspace sharedWorkspace] openURLs:@[url] withApplicationAtURL:appURL configuration:config completionHandler:nil];
        
        // NOTE TO SELF: For some dumb reason the above fails with a sandboxing error, but the below works:
        
        [[NSWorkspace sharedWorkspace] openURL:url];
        
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
    [self importGyroflowProjectWithOptionalURL:nil];
}

//---------------------------------------------------------
// BUTTON: 'Load Last Gyroflow Project'
//---------------------------------------------------------
- (void)buttonLoadLastGyroflowProject {
    NSLog(@"[Gyroflow Toolbox Renderer] Load Last Gyroflow Project Pressed!");
    
    if ([self canReadGyroflowPreferencesFile]) {
        //---------------------------------------------------------
        // We can read the Gyroflow Preferences file:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] We can read the preferences file.");
        [self readLastProjectFromGyroflowPreferencesFile];
    } else {
        //---------------------------------------------------------
        // We can't read the Gyroflow Preferences file, so lets
        // try get sandbox access:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] We can't read the preferences file.");
        NSURL* gyroflowPlistURL = [self getGyroflowPreferencesFileURL];
        [self requestSandboxAccessWithURL:gyroflowPlistURL];
    }
}

//---------------------------------------------------------
// BUTTON: 'Reload Gyroflow Project'
//---------------------------------------------------------
- (void)buttonReloadGyroflowProject {
    
    //---------------------------------------------------------
    // Trash all the caches in Rust land:
    //---------------------------------------------------------
    uint32_t cacheSize = trashCache();
    NSLog(@"[Gyroflow Toolbox Renderer]: Rust MANAGER_CACHE size after trashing (should be zero): %u", cacheSize);
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4'. This shouldn't happen, so it's probably a bug."];
        return;
    }
        
    //---------------------------------------------------------
    // Use the Action API to allow us to change the parameters:
    //---------------------------------------------------------
    [actionAPI startAction:self];
    
    //---------------------------------------------------------
    // Load the Parameter Retrieval API:
    //---------------------------------------------------------
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    if (paramGetAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterRetrievalAPI_v6'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }
    
    //---------------------------------------------------------
    // Get the encoded bookmark string:
    //---------------------------------------------------------
    NSString *encodedBookmark;
    [paramGetAPI getStringParameterValue:&encodedBookmark fromParameter:kCB_GyroflowProjectBookmarkData];
    
    //---------------------------------------------------------
    // Make sure there's actually encoded bookmark data:
    //---------------------------------------------------------
    if ([encodedBookmark isEqualToString:@""]) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"There's no previous security-scoped bookmark data found.\n\nPlease make sure you import a Gyroflow Project before attempting to reload."];
        return;
    }
    
    //---------------------------------------------------------
    // Decode the Base64 bookmark data:
    //---------------------------------------------------------
    NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                              options:0] autorelease];

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
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]]];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Parameter Set API:
    //---------------------------------------------------------
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (paramSetAPI == nil)
    {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxParameterSettingAPI_v5'.\n\nThis shouldn't happen, so it's probably a bug."];
        return;
    }

    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    [url startAccessingSecurityScopedResource];
    
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
    [url stopAccessingSecurityScopedResource];
    if (readError != nil) {
        //---------------------------------------------------------
        // Stop Action API:
        //---------------------------------------------------------
        [actionAPI endAction:self];
        
        [self showAlertWithMessage:@"An error has occurred." info:[NSString stringWithFormat:@"Failed to read Gyroflow Project file due to:\n\n%@", [readError localizedDescription]]];
        return;
    }
    
    //---------------------------------------------------------
    // Update 'Gyroflow Project Data':
    //---------------------------------------------------------
    [paramSetAPI setParameterFlags:kFxParameterFlag_DEFAULT toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectData toParameter:kCB_GyroflowProjectData];
    [paramSetAPI setParameterFlags:kFxParameterFlag_HIDDEN toParameter:kCB_GyroflowProjectData];
        
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
    [self showAlertWithMessage:@"Success!" info:@"The Gyroflow Project has been successfully reloaded from disk."];
}

//---------------------------------------------------------
//
#pragma mark - Import Dropped Clip
//
//---------------------------------------------------------

//---------------------------------------------------------
// Import Dropped Media:
//---------------------------------------------------------
- (void)importDroppedMedia:(NSURL*)url {
    
    if (url == nil) {
        [self showAlertWithMessage:@"An error has occurred" info:@"The dropped item contains no data."];
        return;
    }
    
    NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia URL: %@", [url path]);
    
    NSString *extension = [[url pathExtension] lowercaseString];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([extension isEqualToString:@"gyroflow"]) {
        //---------------------------------------------------------
        // If the dragged file is a Gyroflow file, try load it:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] It's a Gyroflow Project!");
        [self importGyroflowProjectWithOptionalURL:url];
    } else {
        //---------------------------------------------------------
        // If the dragged file is a Media file, check if there's
        // a Gyroflow Project next to it first:
        //---------------------------------------------------------
        NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File!");
        NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
        NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
        if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
            NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with a Gyroflow Project next to it!");
            [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
        } else {
            NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with no Gyroflow Project next to it!");
            [self importMediaWithOptionalURL:url];
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
   
    if (error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to parse the FCPXML due to:\n\n%@", error.localizedDescription];
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    NSArray *mediaRepNodes = [xmlDoc nodesForXPath:@"//media-rep" error:&error];
    
    if (error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Error extracting media-rep nodes:\n\n%@", error.localizedDescription];
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    for (NSXMLElement *node in mediaRepNodes) {
        NSString *src = [[node attributeForName:@"src"] stringValue];
        if (src) {
            url = [NSURL URLWithString:src];
        }
    }
    
    if (url == nil) {
        [self showAlertWithMessage:@"An error has occurred" info:@"Failed to get the media path from the FCPXML."];
        return;
    }
        
    NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
        [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
    } else {
        [self importMediaWithOptionalURL:url];
    }
}

//---------------------------------------------------------
//
#pragma mark - Open Last Gyroflow Project
//
//---------------------------------------------------------

//---------------------------------------------------------
// Request Sandbox access to the Gyroflow Preferences file:
//---------------------------------------------------------
- (void)requestSandboxAccessWithURL:(NSURL*)gyroflowPlistURL {
    //---------------------------------------------------------
    // Show popup with instructions:
    //---------------------------------------------------------
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
    alert.alertStyle        = NSAlertStyleInformational;
    alert.messageText       = @"Permission Required";
    alert.informativeText   = @"Gyroflow Toolbox requires explicit permission to access your Gyroflow Preferences, so that it can determine the last opened project.\n\nPlease click 'Grant Access' on the next Open Folder window to continue.";
    [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result){
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
        
        [panel beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result){
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
            [userDefaults release];
                
            [url stopAccessingSecurityScopedResource];
            
            [self readLastProjectFromGyroflowPreferencesFile];
        }];
    }];
}

//---------------------------------------------------------
// Can we read the Gyroflow Preferences File?
//---------------------------------------------------------
- (BOOL)canReadGyroflowPreferencesFile {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] init];
    NSData *gyroFlowPreferencesBookmarkData = [userDefaults dataForKey:@"gyroFlowPreferencesBookmarkData"];
    [userDefaults release];
    
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
        NSLog(@"[Gyroflow Toolbox Renderer] Failed to read Gyroflow Preferences Bookmark Data: %@", bookmarkError.localizedDescription);
        return NO;
    }
    
    if (staleBookmark) {
        NSLog(@"[Gyroflow Toolbox Renderer] Stale Gyroflow Preferences Bookmark.");
        return NO;
    }
    
    if (url == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Gyroflow Preferences Bookmark is nil.");
        return NO;
    }
            
    if (![url startAccessingSecurityScopedResource]) {
        NSLog(@"[Gyroflow Toolbox Renderer] Failed to start accessing the security scope resource for the Gyroflow Preferences.");
        return NO;
    }
    
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfURL:url];
    
    [url stopAccessingSecurityScopedResource];
    
    if (preferences == nil) {
        NSLog(@"[Gyroflow Toolbox Renderer] Gyroflow Preferences Dictionary is nil.");
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
    [userDefaults release];
    
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
    
    if (preferences == nil) {
        NSString *errorMessage = @"Failed to read the Gyroflow's Preferences file.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return;
    }
    
    NSString *lastProjectPath = [preferences valueForKey:@"lastProject"];
    NSURL *lastProjectURL = [NSURL fileURLWithPath:lastProjectPath];
    
    [self importGyroflowProjectWithOptionalURL:lastProjectURL];
}

//---------------------------------------------------------
//
#pragma mark - Import Functions
//
//---------------------------------------------------------

//---------------------------------------------------------
// Import Gyroflow Project with Optional URL:
//---------------------------------------------------------
- (void)importMediaWithOptionalURL:(NSURL*)optionalURL {
    
    NSLog(@"[Gyroflow Toolbox Renderer] Import Media File!");
    
    NSURL *url = nil;
    BOOL isAccessible = [optionalURL startAccessingSecurityScopedResource];
    
    if (isAccessible) {
        NSLog(@"[Gyroflow Toolbox Renderer] importMediaWithOptionalURL has an accessible NSURL!");
        url = optionalURL;
    } else {
        //---------------------------------------------------------
        // Setup an NSOpenPanel:
        //---------------------------------------------------------
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        [panel setCanChooseDirectories:NO];
        [panel setCanCreateDirectories:YES];
        [panel setCanChooseFiles:YES];
        [panel setAllowsMultipleSelection:NO];
        [panel setDirectoryURL:optionalURL];
        
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
        [panel setAllowedContentTypes:allowedContentTypes];
        
        //---------------------------------------------------------
        // Open the panel:
        //---------------------------------------------------------
        NSModalResponse result = [panel runModal];
        if (result != NSModalResponseOK) {
            return;
        }
        
        url = [panel URL];
        
        //---------------------------------------------------------
        // Start accessing security scoped resource:
        //---------------------------------------------------------
        BOOL startedOK = [url startAccessingSecurityScopedResource];
        if (startedOK == NO) {
            [self showAlertWithMessage:@"An error has occurred." info:@"Failed to startAccessingSecurityScopedResource. This shouldn't happen."];
            return;
        }
    }
        
    NSString *path = [url path];
    
    NSLog(@"[Gyroflow Toolbox Renderer] Import Media File Path: %@", path);
       
    const char* importResult = importMediaFile(
                                               [path UTF8String]        // const char*
                                               );
    
    NSString *resultString = [NSString stringWithUTF8String: importResult];
    NSLog(@"[Gyroflow Toolbox Renderer] resultString: %@", resultString);
        
    if (resultString == nil || [resultString isEqualToString:@"FAIL"]) {
        [self showAlertWithMessage:@"An error has occurred" info:@"Failed to generate a Gyroflow Project from the Media File."];
        return;
    }
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen."];
        return;
    }
    
    NSString *selectedGyroflowProjectFile            = [[url lastPathComponent] stringByDeletingPathExtension];
    NSString *selectedGyroflowProjectPath            = [[[url lastPathComponent] stringByDeletingPathExtension] stringByAppendingString:@".gyroflow"];
    NSString *selectedGyroflowProjectBookmarkData    = @"";
    
    //---------------------------------------------------------
    // Read the JSON data:
    //---------------------------------------------------------
    NSData *data = [resultString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    
    if (jsonError != nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"There was an unexpected error reading the JSON data:\n\n%@", jsonError.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Failed to open Gyroflow Project" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure there's Gyro Data in the Gyroflow Project:
    //---------------------------------------------------------
    const char* hasData = doesGyroflowProjectContainStabilisationData([resultString UTF8String]);
    NSString *hasDataResult = [NSString stringWithUTF8String: hasData];
    NSLog(@"[Gyroflow Toolbox Renderer] hasDataResult: %@", hasDataResult);
    if (hasDataResult == nil || ![hasDataResult isEqualToString:@"PASS"]) {
        NSString *errorMessage = @"The Gyroflow file you imported doesn't seem to contain any gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including gyro data)' option.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Gyro Data Not Found." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the current 'FOV' value:
    //---------------------------------------------------------
    NSDictionary *stabilizationData = [jsonData objectForKey:@"stabilization"];
    NSNumber *fov = [stabilizationData objectForKey:@"fov"];
    
    //---------------------------------------------------------
    // Get the current 'Smoothness' value:
    //---------------------------------------------------------
    NSArray *smoothnessParams = [stabilizationData objectForKey:@"smoothing_params"];
    NSNumber *smoothness = nil;
    for (NSDictionary *param in smoothnessParams) {
        if ([param[@"name"] isEqualToString:@"smoothness"]) {
            smoothness = param[@"value"];
            break;
        }
    }
    
    //---------------------------------------------------------
    // Get the current 'Lens Correction' value:
    //---------------------------------------------------------
    NSNumber *lensCorrection = [stabilizationData objectForKey:@"lens_correction_amount"];
    
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
        NSString *errorMessage = @"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
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
    [paramSetAPI setStringParameterValue:resultString toParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Update 'Loaded Gyroflow Project' Text Box:
    //---------------------------------------------------------
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];
    
    //---------------------------------------------------------
    // Set parameters from Gyroflow Project file:
    //---------------------------------------------------------
    if (fov != nil) {
        [paramSetAPI setFloatValue:[fov floatValue] toParameter:kCB_FOV atTime:kCMTimeZero];
    }
    if (smoothness != nil) {
        [paramSetAPI setFloatValue:[smoothness floatValue] toParameter:kCB_Smoothness atTime:kCMTimeZero];
    }
    if (lensCorrection != nil) {
        [paramSetAPI setFloatValue:[lensCorrection floatValue] * 100.0 toParameter:kCB_LensCorrection atTime:kCMTimeZero];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Stop accessing security scoped resource:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // Show Victory Message:
    //---------------------------------------------------------
    [self showAlertWithMessage:@"Success!" info:@"The Gyroflow Project has been successfully imported.\n\nYou can now adjust the parameters as required."];
    
}

//---------------------------------------------------------
// Import Gyroflow Project with Optional URL:
//---------------------------------------------------------
- (void)importGyroflowProjectWithOptionalURL:(NSURL*)optionalURL {
    
    NSLog(@"[Gyroflow Toolbox Renderer] Import Gyroflow Project with Optional URL Triggered: %@", optionalURL);
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen."];
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
    [panel setDirectoryURL:optionalURL];
        
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
    if (result != NSModalResponseOK) {
        return;
    }

    //---------------------------------------------------------
    // Start accessing security scoped resource:
    //---------------------------------------------------------
    NSURL *url = [panel URL];
    BOOL startedOK = [url startAccessingSecurityScopedResource];
    if (startedOK == NO) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Failed to startAccessingSecurityScopedResource. This shouldn't happen."];
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
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [bookmarkError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    if (bookmark == nil) {
        NSString *errorMessage = @"Bookmark data is nil. This shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    NSString *selectedGyroflowProjectFile            = [[url lastPathComponent] stringByDeletingPathExtension];
    NSString *selectedGyroflowProjectPath            = [url path];
    NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
    
    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&readError];
    if (readError != nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to read Gyroflow Project File due to:\n\n%@", [readError localizedDescription]];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Read the JSON data:
    //---------------------------------------------------------
    NSData *data = [selectedGyroflowProjectData dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
    
    if (jsonError != nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"There was an unexpected error reading the JSON data:\n\n%@", jsonError.localizedDescription];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Failed to open Gyroflow Project" info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Make sure there's Gyro Data in the Gyroflow Project:
    //---------------------------------------------------------
    const char* hasData = doesGyroflowProjectContainStabilisationData([selectedGyroflowProjectData UTF8String]);
    NSString *hasDataResult = [NSString stringWithUTF8String: hasData];
    NSLog(@"[Gyroflow Toolbox Renderer] hasDataResult: %@", hasDataResult);
    if (hasDataResult == nil || ![hasDataResult isEqualToString:@"PASS"]) {
        NSString *errorMessage = @"The Gyroflow file you imported doesn't seem to contain any gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including gyro data)' option.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Gyro Data Not Found." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get the current 'FOV' value:
    //---------------------------------------------------------
    NSDictionary *stabilizationData = [jsonData objectForKey:@"stabilization"];
    NSNumber *fov = [stabilizationData objectForKey:@"fov"];
        
    //---------------------------------------------------------
    // Get the current 'Smoothness' value:
    //---------------------------------------------------------
    NSArray *smoothnessParams = [stabilizationData objectForKey:@"smoothing_params"];
    NSNumber *smoothness = nil;
    for (NSDictionary *param in smoothnessParams) {
        if ([param[@"name"] isEqualToString:@"smoothness"]) {
            smoothness = param[@"value"];
            break;
        }
    }
    
    //---------------------------------------------------------
    // Get the current 'Lens Correction' value:
    //---------------------------------------------------------
    NSNumber *lensCorrection = [stabilizationData objectForKey:@"lens_correction_amount"];
            
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
        NSString *errorMessage = @"Unable to retrieve FxParameterSettingAPI_v5 in 'selectFileButtonPressed'. This shouldn't happen.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
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
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectData toParameter:kCB_GyroflowProjectData];
    
    //---------------------------------------------------------
    // Update 'Loaded Gyroflow Project' Text Box:
    //---------------------------------------------------------
    [paramSetAPI setStringParameterValue:selectedGyroflowProjectFile toParameter:kCB_LoadedGyroflowProject];

    //---------------------------------------------------------
    // Set parameters from Gyroflow Project file:
    //---------------------------------------------------------
    if (fov != nil) {
        [paramSetAPI setFloatValue:[fov floatValue] toParameter:kCB_FOV atTime:kCMTimeZero];
    }
    if (smoothness != nil) {
        [paramSetAPI setFloatValue:[smoothness floatValue] toParameter:kCB_Smoothness atTime:kCMTimeZero];
    }
    if (lensCorrection != nil) {
        [paramSetAPI setFloatValue:[lensCorrection floatValue] * 100.0 toParameter:kCB_LensCorrection atTime:kCMTimeZero];
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Stop accessing security scoped resource:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // Show Victory Message:
    //---------------------------------------------------------
    [self showAlertWithMessage:@"Success!" info:@"The Gyroflow Project has been successfully imported.\n\nYou can now adjust the parameters as required."];
}

//---------------------------------------------------------
//
#pragma mark - Helpers
//
//---------------------------------------------------------

//---------------------------------------------------------
// Get user home directory path:
//---------------------------------------------------------
- (NSString*)getUserHomeDirectoryPath {
    struct passwd *pw = getpwuid(getuid());
    assert(pw);
    return [NSString stringWithUTF8String:pw->pw_dir];
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
- (void)showAlertWithMessage:(NSString*)message info:(NSString*)info
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert          = [[[NSAlert alloc] init] autorelease];
        alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = message;
        alert.informativeText   = info;
        [alert runModal];
    });
}

@end
