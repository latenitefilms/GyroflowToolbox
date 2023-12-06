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
        
        NSString* logPath = [applicationSupportDirectory stringByAppendingString:@"/FxPlug.log"];
        
        freopen([logPath fileSystemRepresentation],"a+",stderr);
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        
        NSLog(@"[Gyroflow Toolbox Renderer] --------------------------------- START OF NEW SESSION ---------------------------------");
        NSLog(@"[Gyroflow Toolbox Renderer] Version: %@ (%@)", version, build);
        NSLog(@"[Gyroflow Toolbox Renderer] applicationSupportDirectory: '%@'", applicationSupportDirectory);
        
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
        lensProfilesLookup = [self newLensProfileIdentifiersFromDirectory:lensProfilesPath];
        
        //NSLog(@"[Gyroflow Toolbox Renderer] lensProfilesLookup: %@", lensProfilesLookup);
        
        //---------------------------------------------------------
        // Cache the API Manager:
        //---------------------------------------------------------
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
                                                        buttonTitle:@"Launch Gyroflow"];
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
        
        NSRect frameRect = NSMakeRect(0, 0, 200, 324); // x y w h
        NSView* view = [[HeaderView alloc] initWithFrame:frameRect];
        
        headerView = view;
        return view;
    } else if (parameterID == kCB_OpenUserGuide) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_OpenUserGuide
                                                        buttonTitle:@"Open User Guide"];
        openUserGuideView = view;
        return view;
    } else if (parameterID == kCB_Settings) {
        NSView* view = [[CustomButtonView alloc] initWithAPIManager:_apiManager
                                                       parentPlugin:self
                                                           buttonID:kCB_Settings
                                                        buttonTitle:@"Settings"];
        settingsView = view;
        return view;
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
        //
        // let mut param = param_set.param_define_double("FOV")?;
        // param.set_default(1.0)?;
        // param.set_display_min(0.1)?;
        // param.set_display_max(3.0)?;
        // param.set_label("FOV")?;
        // param.set_hint("FOV")?;
        // let _ = param.set_script_name("FOV");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("Smoothness")?;
        // param.set_default(0.5)?;
        // param.set_display_min(0.01)?;
        // param.set_display_max(3.0)?;
        // param.set_label("Smoothness")?;
        // param.set_hint("Smoothness")?;
        // let _ = param.set_script_name("Smoothness");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("LensCorrectionStrength")?;
        // param.set_default(100.0)?;
        // param.set_display_min(0.0)?;
        // param.set_display_max(100.0)?;
        // param.set_label("Lens correction")?;
        // param.set_hint("Lens correction")?;
        // let _ = param.set_script_name("LensCorrectionStrength");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("HorizonLockAmount")?;
        // param.set_default(0.0)?;
        // param.set_display_min(0.0)?;
        // param.set_display_max(100.0)?;
        // param.set_label("Horizon lock")?;
        // param.set_hint("Horizon lock amount")?;
        // let _ = param.set_script_name("HorizonLockAmount");
        // param.set_parent("AdjustGroup")?;//
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
        //
        // let mut param = param_set.param_define_double("HorizonLockRoll")?;
        // param.set_default(0.0)?;
        // param.set_display_min(-100.0)?;
        // param.set_display_max(100.0)?;
        // param.set_label("Horizon roll")?;
        // param.set_hint("Horizon lock roll adjustment")?;
        // let _ = param.set_script_name("HorizonLockRoll");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("PositionX")?;
        // param.set_default(0.0)?;
        // param.set_display_min(-100.0)?;
        // param.set_display_max(100.0)?;
        // param.set_label("Position offset X")?;
        // let _ = param.set_script_name("PositionX");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("PositionY")?;
        // param.set_default(0.0)?;
        // param.set_display_min(-100.0)?;
        // param.set_display_max(100.0)?;
        // param.set_label("Position offset Y")?;
        // let _ = param.set_script_name("PositionY");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("InputRotation")?;
        // param.set_default(0.0)?;
        // param.set_display_min(-360.0)?;
        // param.set_display_max(360.0)?;
        // param.set_label("Input rotation")?;
        // let _ = param.set_script_name("InputRotation");
        // param.set_parent("AdjustGroup")?;
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
        //
        // let mut param = param_set.param_define_double("Rotation")?;
        // param.set_default(0.0)?;
        // param.set_display_min(-360.0)?;
        // param.set_display_max(360.0)?;
        // param.set_label("Video rotation")?;
        // let _ = param.set_script_name("Rotation");
        // param.set_parent("AdjustGroup")?;
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
        // ADD PARAMETER: 'Settings' Button
        //---------------------------------------------------------
        if (![paramAPI addCustomParameterWithName:@""
                                      parameterID:kCB_Settings
                                     defaultValue:@0
                                   parameterFlags:kFxParameterFlag_CUSTOM_UI | kFxParameterFlag_NOT_ANIMATABLE])
        {
            if (error != NULL) {
                NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_Settings"};
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
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Media Path' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Media Path"
                                  parameterID:kCB_MediaPath
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_MediaPath"};
            *error = [NSError errorWithDomain:FxPlugErrorDomain
                                         code:kFxError_InvalidParameter
                                     userInfo:userInfo];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // ADD PARAMETER: 'Media Bookmark Data' Text Box
    //---------------------------------------------------------
    if (![paramAPI addStringParameterWithName:@"Media Bookmark Data"
                                  parameterID:kCB_MediaBookmarkData
                                 defaultValue:@""
                               parameterFlags:kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE])
    {
        if (error != NULL) {
            NSDictionary* userInfo = @{NSLocalizedDescriptionKey : @"[Gyroflow Toolbox Renderer] Unable to add parameter: kCB_MediaBookmarkData"};
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
        //NSLog(@"[Gyroflow Toolbox Renderer] Disable Gyroflow Stretch Changed!");
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
        
    //---------------------------------------------------------
    // If the Gyroflow Project data is base64 encoded, try
    // to decode it first, otherwise pass the original string:
    //---------------------------------------------------------
    NSData *base64EncodedData = [[NSData alloc] initWithBase64EncodedString:gyroflowData options:0];
    if (base64EncodedData != nil) {
        NSString *decodedGyroflowData = [[NSString alloc] initWithData:base64EncodedData encoding:NSUTF8StringEncoding];
        if (decodedGyroflowData != nil) {
            params.gyroflowData = decodedGyroflowData;
            
            //---------------------------------------------------------
            // Release memory:
            //---------------------------------------------------------
            [decodedGyroflowData release];
        }
        
        //---------------------------------------------------------
        // Release memory:
        //---------------------------------------------------------
        [base64EncodedData release];
    } else {
        params.gyroflowData = gyroflowData;
    }
    
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
                    outputHeight:(float)outputHeight outputWidth:(float)outputWidth
                    sourceImages:(NSArray<FxImageTile *> * _Nonnull)sourceImages
{
    MetalDeviceCache* deviceCache       = [MetalDeviceCache deviceCache];
    MTLPixelFormat pixelFormat          = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
    id<MTLCommandQueue> commandQueue    = [deviceCache commandQueueWithRegistryID:destinationImage.deviceRegistryID
                                                                      pixelFormat:pixelFormat];
    if (commandQueue == nil)
    {
        NSString *errorMessage = @"FATAL ERROR: commandQueue was nil when attempting to show an error message.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
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
    
    id<MTLTexture> inputTexture         = [loader newTextureWithName:errorMessageID scaleFactor:1.0 bundle:[NSBundle mainBundle] options:options error:nil];
    id<MTLTexture> outputTexture        = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:destinationImage.deviceRegistryID]];
    
    //---------------------------------------------------------
    // If square pixels, we'll manipulate the height and y
    // axis manually:
    //---------------------------------------------------------
    float correctedHeight = outputHeight;
    float differenceBetweenHeights = 0;
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
    colorAttachmentDescriptor.clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0); // White
    colorAttachmentDescriptor.loadAction = MTLLoadActionClear;
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments [ 0 ] = colorAttachmentDescriptor;
    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    
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
    if (sourceImages[0].ioSurface == nil) {
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
    // Get the Device Registry ID from the Destination Image:
    //---------------------------------------------------------
    uint64_t deviceRegistryID = destinationImage.deviceRegistryID;
    
    //---------------------------------------------------------
    // Setup the Pixel Format based on the destination image:
    //---------------------------------------------------------
    MTLPixelFormat pixelFormat = [MetalDeviceCache MTLPixelFormatForImageTile:destinationImage];
    
    //---------------------------------------------------------
    // Setup a new Command Queue for FxPlug4:
    //---------------------------------------------------------
    id<MTLCommandQueue> commandQueue = [deviceCache commandQueueWithRegistryID:deviceRegistryID
                                                                   pixelFormat:pixelFormat];
    
    //---------------------------------------------------------
    // If the Command Queue wasn't created, abort:
    //---------------------------------------------------------
    if (commandQueue == nil)
    {
        //---------------------------------------------------------
        // Output error message to Console:
        //---------------------------------------------------------
        NSString *errorMessage = @"FATAL ERROR - Unable to get command queue. May need to increase cache size.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        if (outError != NULL) {
            *outError = [NSError errorWithDomain:FxPlugErrorDomain
                                            code:kFxError_InvalidParameter
                                        userInfo:@{ NSLocalizedDescriptionKey : errorMessage }];
        }
        return NO;
    }
    
    //---------------------------------------------------------
    // Setup our input texture:
    //
    // Retrieve a Metal texture from the IOSurface for
    // rendering on the passed-in device. The returned texture
    // is autoreleased
    //---------------------------------------------------------
    id<MTLTexture> inputTexture = [sourceImages[0] metalTextureForDevice:[deviceCache deviceWithRegistryID:deviceRegistryID]];
    
    //---------------------------------------------------------
    // Setup our output texture:
    //
    // Retrieve a Metal texture from the IOSurface for
    // rendering on the passed-in device. The returned texture
    // is autoreleased
    //---------------------------------------------------------
    id<MTLTexture> outputTexture = [destinationImage metalTextureForDevice:[deviceCache deviceWithRegistryID:deviceRegistryID]];
    
    //---------------------------------------------------------
    // Create a temporary output texture to go from Rust
    // to Objective-C land, that we have full control of:
    //---------------------------------------------------------
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.textureType = MTLTextureType2D;
    textureDescriptor.pixelFormat = pixelFormat;
    textureDescriptor.width = outputTexture.width;
    textureDescriptor.height = outputTexture.height;
    id<MTLTexture> tempTexture = [[deviceCache deviceWithRegistryID:deviceRegistryID] newTextureWithDescriptor:textureDescriptor];
    [textureDescriptor release];
    
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
        // Release the temp texture before aborting:
        //---------------------------------------------------------
        [tempTexture release];
        
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
    // Retain the Textures whilst in Rust-land:
    //---------------------------------------------------------
    [inputTexture retain];
    
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
                                      tempTexture,              // MTLTexture
                                      commandQueue              // MTLCommandQueue
                                      );
        
    NSString *resultString = [NSString stringWithUTF8String: result];
    
    //---------------------------------------------------------
    // Release the Input Texture:
    //---------------------------------------------------------
    if (inputTexture != nil) {
        [inputTexture setPurgeableState:MTLPurgeableStateEmpty];
        [inputTexture release];
        inputTexture = nil;
    }
    
    //---------------------------------------------------------
    // Gyroflow Core had an error, so abort:
    //---------------------------------------------------------
    if (![resultString isEqualToString:@"DONE"]) {
        //---------------------------------------------------------
        // Release the Temp Texture:
        //---------------------------------------------------------
        [tempTexture release];
        
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

    
    //---------------------------------------------------------
    // Copy the Temporary Texture to the Output Texture via
    // a Command Buffer:
    //---------------------------------------------------------
    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    
    id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
    
    [blitEncoder copyFromTexture:tempTexture
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake([tempTexture width], [tempTexture height], 1)
                       toTexture:outputTexture
                destinationSlice:0
                destinationLevel:0
               destinationOrigin:MTLOriginMake(0, 0, 0)];
    
    [blitEncoder endEncoding];

    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
        
    //---------------------------------------------------------
    // Release the Temporary Texture:
    //---------------------------------------------------------
    if (tempTexture != nil) {
        [tempTexture setPurgeableState:MTLPurgeableStateEmpty];
        [tempTexture release];
        tempTexture = nil;
    }
    
    //---------------------------------------------------------
    // Return the command queue back into the cache,
    // so we can re-use it again:
    //---------------------------------------------------------
    [deviceCache returnCommandQueueToCache:commandQueue];
        
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
        NSMenu *settingsMenu = [[[NSMenu alloc] initWithTitle:@"Settings"] autorelease];
        
        //---------------------------------------------------------
        // Create the "Show Alerts" sub-menu:
        //---------------------------------------------------------
        NSMenu *disableAlertSubMenu = [[[NSMenu alloc] initWithTitle:@"Disable Alerts"] autorelease];
        
        //---------------------------------------------------------
        // "Show Alerts" Sub Menu Items:
        //---------------------------------------------------------
        {
            //---------------------------------------------------------
            // Load Preset/Lens Profile Success:
            //---------------------------------------------------------
            NSMenuItem *suppressLoadPresetLensProfileSuccess   = [[[NSMenuItem alloc] initWithTitle:@"Load Preset/Lens Profile Success" action:@selector(toggleMenuItem:) keyEquivalent:@""] autorelease];
            suppressLoadPresetLensProfileSuccess.identifier    = @"suppressLoadPresetLensProfileSuccess";
            suppressLoadPresetLensProfileSuccess.target        = self;
            suppressLoadPresetLensProfileSuccess.enabled       = YES;
            suppressLoadPresetLensProfileSuccess.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressLoadPresetLensProfileSuccess"]];
            [disableAlertSubMenu addItem:suppressLoadPresetLensProfileSuccess];
            
            //---------------------------------------------------------
            // No Lens Profile Detected:
            //---------------------------------------------------------
            NSMenuItem *suppressNoLensProfileDetected   = [[[NSMenuItem alloc] initWithTitle:@"No Lens Profile Detected" action:@selector(toggleMenuItem:) keyEquivalent:@""] autorelease];
            suppressNoLensProfileDetected.identifier    = @"suppressNoLensProfileDetected";
            suppressNoLensProfileDetected.target        = self;
            suppressNoLensProfileDetected.enabled       = YES;
            suppressNoLensProfileDetected.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressNoLensProfileDetected"]];
            [disableAlertSubMenu addItem:suppressNoLensProfileDetected];
            
            //---------------------------------------------------------
            // Request Sandbox Access:
            //---------------------------------------------------------
            NSMenuItem *suppressRequestSandboxAccessAlert   = [[[NSMenuItem alloc] initWithTitle:@"Request Sandbox Access" action:@selector(toggleMenuItem:) keyEquivalent:@""] autorelease];
            suppressRequestSandboxAccessAlert.identifier    = @"suppressRequestSandboxAccessAlert";
            suppressRequestSandboxAccessAlert.target        = self;
            suppressRequestSandboxAccessAlert.enabled       = YES;
            suppressRequestSandboxAccessAlert.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressRequestSandboxAccessAlert"]];
            [disableAlertSubMenu addItem:suppressRequestSandboxAccessAlert];
            
            //---------------------------------------------------------
            // Successfully Imported:
            //---------------------------------------------------------
            NSMenuItem *suppressSuccessfullyImported   = [[[NSMenuItem alloc] initWithTitle:@"Successfully Imported" action:@selector(toggleMenuItem:) keyEquivalent:@""] autorelease];
            suppressSuccessfullyImported.identifier    = @"suppressSuccessfullyImported";
            suppressSuccessfullyImported.target        = self;
            suppressSuccessfullyImported.enabled       = YES;
            suppressSuccessfullyImported.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressSuccessfullyImported"]];
            [disableAlertSubMenu addItem:suppressSuccessfullyImported];
            
            //---------------------------------------------------------
            // Successfully Reloaded:
            //---------------------------------------------------------
            NSMenuItem *suppressSuccessfullyReloaded   = [[[NSMenuItem alloc] initWithTitle:@"Successfully Reloaded" action:@selector(toggleMenuItem:) keyEquivalent:@""] autorelease];
            suppressSuccessfullyReloaded.identifier    = @"suppressSuccessfullyReloaded";
            suppressSuccessfullyReloaded.target        = self;
            suppressSuccessfullyReloaded.enabled       = YES;
            suppressSuccessfullyReloaded.state         = [self boolToControlState:[userDefaults boolForKey:@"suppressSuccessfullyReloaded"]];
            [disableAlertSubMenu addItem:suppressSuccessfullyReloaded];
        }
        
        //---------------------------------------------------------
        // Add "Show Alerts" Sub Menu:
        //---------------------------------------------------------
        NSMenuItem *disableAlertSubMenuItem = [[[NSMenuItem alloc] initWithTitle:@"Disabled Alerts" action:nil keyEquivalent:@""] autorelease];
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
        // Show Log File in Finder:
        //---------------------------------------------------------
        NSMenuItem *showLogFileInFinder    = [[[NSMenuItem alloc] initWithTitle:@"Show Log Files in Finder" action:@selector(showLogFileInFinder:) keyEquivalent:@""] autorelease];
        showLogFileInFinder.target         = self;
        showLogFileInFinder.enabled        = YES;
        [settingsMenu addItem:showLogFileInFinder];
        
        //---------------------------------------------------------
        // Reset Settings:
        //---------------------------------------------------------
        NSMenuItem *resetSettings       = [[[NSMenuItem alloc] initWithTitle:@"Reset All Settings" action:@selector(resetSettings:) keyEquivalent:@""] autorelease];
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
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
            
            //---------------------------------------------------------
            // Release memory:
            //---------------------------------------------------------
            [decodedGyroflowData release];
        }
        
        //---------------------------------------------------------
        // Release memory:
        //---------------------------------------------------------
        [base64EncodedData release];
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
    
    if (gyroflowProjectName != nil || [gyroflowProjectName isEqualToString:@""]) {
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
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
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
            
            //---------------------------------------------------------
            // Release memory:
            //---------------------------------------------------------
            [decodedGyroflowData release];
        }
        
        //---------------------------------------------------------
        // Release memory:
        //---------------------------------------------------------
        [base64EncodedData release];
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
              
        NSString *path = lensProfilesLookup[loadedLensIdentifierInGyroflowProjectString];
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
        NSAlert *alert                  = [[[NSAlert alloc] init] autorelease];
        alert.icon                      = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Imported!";
        alert.informativeText           = message;
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressLoadPresetLensProfileSuccess"];
            }
            
            //---------------------------------------------------------
            // Close the alert:
            //---------------------------------------------------------
            [alert.window orderOut:nil];
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
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
    [self importGyroflowProjectWithOptionalURL:nil];
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
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
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
    id<FxParameterRetrievalAPI_v6> paramGetAPI = [_apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
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
            NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:mediaBookmarkDataString
                                                                           options:0] autorelease];
            
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
        id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
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
    NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:encodedBookmark
                                                                   options:0] autorelease];
    
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
    id<FxParameterSettingAPI_v5> paramSetAPI = [_apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
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
        NSAlert *alert                  = [[[NSAlert alloc] init] autorelease];
        alert.icon                      = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Reloaded!";
        alert.informativeText           = @"The Gyroflow Project has been successfully reloaded from disk.";
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressSuccessfullyReloaded"];
            }
            
            //---------------------------------------------------------
            // Close the alert:
            //---------------------------------------------------------
            [alert.window orderOut:nil];
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
- (BOOL)importDroppedMedia:(NSData*)bookmarkData {
    
    /*
     if ([[NSFileManager defaultManager] isReadableFileAtPath:[fileURL path]]) {
     NSLog(@"[Gyroflow Toolbox Renderer] Can read file: %@", [fileURL path]);
     } else {
     NSLog(@"[Gyroflow Toolbox Renderer] Failed to read file: %@", [fileURL path]);
     }
     */
    
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
        return NO;
    }
    
    if (isStale) {
        NSLog(@"[Gyroflow Toolbox Renderer] WARNING - Bookmark is stale: %@", [url path]);
    }
    
    if (![url startAccessingSecurityScopedResource]) {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Could not start accessing the security-scoped bookmark.");
        return NO;
    }
    
    //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia URL: %@", [url path]);
    
    NSString *extension = [[url pathExtension] lowercaseString];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([extension isEqualToString:@"gyroflow"]) {
        //---------------------------------------------------------
        // If the dragged file is a Gyroflow file, try load it:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Gyroflow Project!");
        [self importGyroflowProjectWithOptionalURL:url];
    } else {
        //---------------------------------------------------------
        // If the dragged file is a Media file, check if there's
        // a Gyroflow Project next to it first:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File!");
        NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
        //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
        if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
            //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with a Gyroflow Project next to it!");
            [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
        } else {
            //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with no Gyroflow Project next to it!");
            [self importMediaWithOptionalURL:url];
        }
    }
    
    //---------------------------------------------------------
    // Stop accessing the security scoped resource:
    //---------------------------------------------------------
    [url stopAccessingSecurityScopedResource];
    
    return YES;
}

//---------------------------------------------------------
// Import Dropped Clip:
//---------------------------------------------------------
- (BOOL)importDroppedClip:(NSString*)fcpxmlString {
    
    NSURL *url = nil;
    
    NSError *error;
    NSXMLDocument *xmlDoc = [[[NSXMLDocument alloc] initWithXMLString:fcpxmlString options:0 error:&error] autorelease];
    
    if (error) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to parse the FCPXML due to:\n\n%@", error.localizedDescription];
        [self showAsyncAlertWithMessage:@"An error has occurred" info:errorMessage];
        return NO;
    }
    
    if ([self isValidBRAWToolboxString:fcpxmlString]) {
        //---------------------------------------------------------
        // It's a BRAW Toolbox Clip:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a BRAW clip!");
        
        BRAWToolboxXMLReader *reader = [[[BRAWToolboxXMLReader alloc] init] autorelease];
        NSDictionary *result = [reader readXML:fcpxmlString];
        
        if (![result isKindOfClass:[NSDictionary class]]) {
            [self showAlertWithMessage:@"An error has occurred" info:@"Failed to get the media path from the BRAW Toolbox Clip."];
            return NO;
        }
                
        //NSLog(@"[Gyroflow Toolbox Renderer] result: %@", result);
        
        NSString *filePath = result[@"File Path"];
        NSString *bookmarkData = result[@"Bookmark Data"];
        [self importBRAWToolboxClipWithPath:filePath bookmarkDataString:bookmarkData];
        
        return NO;
    } else {
        //---------------------------------------------------------
        // It's not a BRAW Toolbox Clip:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] It's NOT a BRAW clip!");
        
        NSArray *mediaRepNodes = [xmlDoc nodesForXPath:@"//media-rep" error:&error];
        
        if (error) {
            NSString *errorMessage = [NSString stringWithFormat:@"Error extracting media-rep nodes:\n\n%@", error.localizedDescription];
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAsyncAlertWithMessage:@"An error has occurred" info:errorMessage];
            return NO;
        }
        
        for (NSXMLElement *node in mediaRepNodes) {
            NSString *src = [[node attributeForName:@"src"] stringValue];
            if (src) {
                url = [NSURL URLWithString:src];
            }
        }
        
        if (url == nil) {
            [self showAsyncAlertWithMessage:@"An error has occurred" info:@"Failed to get the media path from the FCPXML."];
            return NO;
        }
        
        NSURL *gyroflowUrl = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
            [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
        } else {
            [self importMediaWithOptionalURL:url];
        }
    }
    
    return YES;
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
        NSAlert *alert                  = [[[NSAlert alloc] init] autorelease];
        alert.icon                      = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Permission Required";
        alert.informativeText           = @"Gyroflow Toolbox requires explicit permission to access your Gyroflow Preferences, so that it can determine the last opened project.\n\nPlease click 'Grant Access' on the next Open Folder window to continue.";
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result) {
            
            //---------------------------------------------------------
            // Close the alert:
            //---------------------------------------------------------
            [alert.window orderOut:nil];
            
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
    
    if (![preferences isKindOfClass:[NSDictionary class]]) {
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
        [self importGyroflowProjectWithOptionalURL:lastProjectURL];
    } else {
        [self showAlertWithMessage:@"No Gyroflow Project Found" info:@"The last Gyroflow Project loaded into Gyroflow no longer exists."];
    }
}

//---------------------------------------------------------
//
#pragma mark - Import Functions
//
//---------------------------------------------------------

//---------------------------------------------------------
// Show Successfully Imported Alert:
//---------------------------------------------------------
- (void)showSuccessfullyImportedAlert {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"suppressSuccessfullyImported"]) {
        NSAlert *alert                  = [[[NSAlert alloc] init] autorelease];
        alert.icon                      = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle                = NSAlertStyleInformational;
        alert.messageText               = @"Successfully Imported!";
        alert.informativeText           = @"The Gyroflow Project has been successfully imported into Final Cut Pro.\n\nYou can now adjust the parameters as required via the Video Inspector.";
        alert.showsSuppressionButton    = YES;
        [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result) {
            if ([alert suppressionButton].state == NSControlStateValueOn) {
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressSuccessfullyImported"];
            }
            
            //---------------------------------------------------------
            // Close the alert:
            //---------------------------------------------------------
            [alert.window orderOut:nil];
        }];
    }
}

//---------------------------------------------------------
// Import Media with Optional URL:
//---------------------------------------------------------
- (BOOL)importMediaWithOptionalURL:(NSURL*)optionalURL {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] FUNCTION: Import Media File with optional URL: %@", optionalURL);
    
    NSURL *url = nil;
    BOOL isAccessible = NO;
    
    if (optionalURL) {
        isAccessible = [[NSFileManager defaultManager] isReadableFileAtPath:[optionalURL path]];
    }
    
    if (isAccessible) {
        //---------------------------------------------------------
        // The file is already accessible in the sandbox, so we
        // don't have to ask the user for permission:
        //---------------------------------------------------------
        //NSLog(@"[Gyroflow Toolbox Renderer] importMediaWithOptionalURL has an accessible NSURL!");
        url = optionalURL;
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
            return NO;
        }
        
        //---------------------------------------------------------
        // Save path for next time...
        //---------------------------------------------------------
        url = [panel URL];
        [userDefaults setObject:[[url path] stringByDeletingLastPathComponent] forKey:@"lastImportMediaPath"];
        
        //---------------------------------------------------------
        // Start accessing security scoped resource:
        //---------------------------------------------------------
        BOOL startedOK = [url startAccessingSecurityScopedResource];
        if (startedOK == NO) {
            NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return NO;
        }
    }
        
    NSString *path = [url path];
    
    //NSLog(@"[Gyroflow Toolbox Renderer] Import Media File Path: %@", path);
    
    //---------------------------------------------------------
    // Use gyroflow_core to import the media file:
    //---------------------------------------------------------
    const char* importResult = importMediaFile(
                                               [path UTF8String]        // const char*
                                               );
    
    NSString *gyroflowProject = [NSString stringWithUTF8String: importResult];
    //NSLog(@"[Gyroflow Toolbox Renderer] gyroflowProject: %@", gyroflowProject);
        
    //---------------------------------------------------------
    // Abort if there's no valid Gyroflow Project:
    //---------------------------------------------------------
    if (gyroflowProject == nil || [gyroflowProject isEqualToString:@"FAIL"]) {
        [self showAlertWithMessage:@"An error has occurred" info:@"Failed to generate a Gyroflow Project from the Media File.\n\nPlease check that the file you tried to import has gyroscope data."];
        return NO;
    }
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
        [self showAlertWithMessage:@"An error has occurred." info:@"Unable to retrieve 'FxCustomParameterActionAPI_v4' in ImportGyroflowProjectView's 'buttonPressed'. This shouldn't happen."];
        return NO;
    }
    
    //---------------------------------------------------------
    // Just the filename (i.e. `A003_A002_1223KO_001`):
    //---------------------------------------------------------
    NSString *selectedGyroflowProjectFile = [[url lastPathComponent] stringByDeletingPathExtension];
    
    //---------------------------------------------------------
    // The Gyroflow path, for example:
    // /Users/chrishocking/Desktop/Gyroflow Test Clips/- AdrianEddy - R3D/A003_A002_1223KO_001.gyroflow
    //---------------------------------------------------------
    NSString *selectedGyroflowProjectPath = [[[url path] stringByDeletingPathExtension] stringByAppendingString:@".gyroflow"];
    
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
    //NSLog(@"[Gyroflow Toolbox Renderer] doesHaveAccurateTimestamps: %@", doesHaveAccurateTimestampsString);
    
    if (doesHaveAccurateTimestampsString == nil || ![doesHaveAccurateTimestampsString isEqualToString:@"YES"]) {
        //---------------------------------------------------------
        // The Gyroflow Project doesn't have accurate timestamps,
        // so we need to launch Gyroflow:
        //---------------------------------------------------------
        NSString *message = @"Requires Synchronization in Gyroflow";
        NSString *info = @"The imported media file needs to be synchronized in Gyroflow before it can be used by Gyroflow Toolbox in Final Cut Pro.\n\nYou will be prompted to save the Gyroflow Project, and then we'll launch Gyroflow to open it.\n\nWhen you have finished synchronizing in Gyroflow, press COMMAND+S to save the project. Then back in Final Cut Pro press the 'Reload Gyroflow Project' button in the Inspector of the Gyroflow Toolbox effect.";
        [self showAlertWithMessage:message info:info];
        requiresGyroflowLaunch = YES;
    }
    
    //---------------------------------------------------------
    // Make sure there's Gyro Data in the Gyroflow Project:
    //---------------------------------------------------------
    if (!requiresGyroflowLaunch) {
        const char* hasData = doesGyroflowProjectContainStabilisationData([gyroflowProject UTF8String]);
        NSString *hasDataResult = [NSString stringWithUTF8String: hasData];
        //NSLog(@"[Gyroflow Toolbox Renderer] hasDataResult: %@", hasDataResult);
        if (hasDataResult == nil || ![hasDataResult isEqualToString:@"YES"]) {
            NSString *errorMessage = @"The file you imported doesn't seem to contain any gyroscope data.\n\nPlease check the media file to make sure it's correct and valid.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"Missing Gyroscope Data" info:errorMessage];
            return NO;
        }
    }
    
    //---------------------------------------------------------
    // Create a new security-scoped bookmark:
    //---------------------------------------------------------
    NSError *bookmarkError = nil;
    NSURLBookmarkCreationOptions bookmarkOptions = NSURLBookmarkCreationWithSecurityScope | NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccess;
    NSData *bookmarkData = [url bookmarkDataWithOptions:bookmarkOptions
                         includingResourceValuesForKeys:nil
                                          relativeToURL:nil
                                                  error:&bookmarkError];
    
    if (bookmarkError != nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"Unable to create security-scoped bookmark in importMediaWithOptionalURL ('%@') due to: %@", url, bookmarkError];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return NO;
    }
    
    if (bookmarkData == nil) {
        NSString *errorMessage = [NSString stringWithFormat:@"Unable to create security-scoped bookmark in importMediaWithOptionalURL ('%@') due to: Bookmark is nil.", url];
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"An error has occurred" info:errorMessage];
        return NO;
    }
    
    NSString *mediaBookmarkData = [bookmarkData base64EncodedStringWithOptions:0];
        
    //---------------------------------------------------------
    // Get default values from the Gyroflow Project:
    //---------------------------------------------------------
    double defaultFOV               = 1.0;
    double defaultSmoothness        = 0.5;
    double defaultLensCorrection    = 100.0;
    double defaultHorizonLock       = 0.0;
    double defaultHorizonRoll       = 0.0;
    double defaultPositionOffsetX   = 0.0;
    double defaultPositionOffsetY   = 0.0;
    double defaultVideoRotation     = 0.0;
    
    const char* getDefaultValuesResult = getDefaultValues(
        [gyroflowProject UTF8String],
        &defaultFOV,
        &defaultSmoothness,
        &defaultLensCorrection,
        &defaultHorizonLock,
        &defaultHorizonRoll,
        &defaultPositionOffsetX,
        &defaultPositionOffsetY,
        &defaultVideoRotation
    );
    
    NSString *getDefaultValuesResultString = [NSString stringWithUTF8String:getDefaultValuesResult];
    //NSLog(@"[Gyroflow Toolbox Renderer] getDefaultValuesResult: %@", getDefaultValuesResultString);
            
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
        return NO;
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
    if ([getDefaultValuesResultString isEqualToString:@"OK"]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultFOV: %f", defaultFOV);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultSmoothness: %f", defaultSmoothness);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultLensCorrection: %f", defaultLensCorrection);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultHorizonLock: %f", defaultHorizonLock);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultHorizonRoll: %f", defaultHorizonRoll);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultPositionOffsetX: %f", defaultPositionOffsetX);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultPositionOffsetY: %f", defaultPositionOffsetY);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultVideoRotation: %f", defaultVideoRotation);
        
        [paramSetAPI setFloatValue:defaultFOV toParameter:kCB_FOV atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultSmoothness toParameter:kCB_Smoothness atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultLensCorrection toParameter:kCB_LensCorrection atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultHorizonLock toParameter:kCB_HorizonLock atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultHorizonRoll toParameter:kCB_HorizonRoll atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultPositionOffsetX toParameter:kCB_PositionOffsetX atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultPositionOffsetY toParameter:kCB_PositionOffsetY atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultVideoRotation toParameter:kCB_VideoRotation atTime:kCMTimeZero];
    } else {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get default values!");
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
    // If we need to Launch Gyroflow:
    //---------------------------------------------------------
    if (requiresGyroflowLaunch) {
        //---------------------------------------------------------
        // This is depreciated, but there's no better way to do
        // it in a sandbox sadly:
        //---------------------------------------------------------
        #pragma GCC diagnostic push
        #pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        [[NSWorkspace sharedWorkspace] openFile:[url path] withApplication:@"Gyroflow"];
        #pragma GCC diagnostic pop
        return YES;
    }
        
    //---------------------------------------------------------
    // Check to see if an official lens is loaded in the
    // Gyroflow Project:
    //---------------------------------------------------------
    const char* officialLensLoaded = isOfficialLensLoaded([gyroflowProject UTF8String]);
    NSString *isOfficialLensLoaded = [NSString stringWithUTF8String:officialLensLoaded];
    //NSLog(@"[Gyroflow Toolbox Renderer] isOfficialLensLoaded: %@", isOfficialLensLoaded);
    if (isOfficialLensLoaded == nil || ![isOfficialLensLoaded isEqualToString:@"YES"]) {
        //---------------------------------------------------------
        // Show popup with instructions:
        //---------------------------------------------------------
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (![defaults boolForKey:@"suppressNoLensProfileDetected"]) {
            NSAlert *alert                  = [[[NSAlert alloc] init] autorelease];
            alert.icon                      = [NSImage imageNamed:@"GyroflowToolbox"];
            alert.alertStyle                = NSAlertStyleInformational;
            alert.messageText               = @"No Lens Profile Detected";
            alert.informativeText           = @"A lens profile could not be automatically detected from the supplied video file.\n\nYou will be prompted to select an appropriate Lens Profile in the next panel.";
            alert.showsSuppressionButton    = YES;
            [alert beginSheetModalForWindow:loadLastGyroflowProjectView.window completionHandler:^(NSModalResponse result) {
                
                //---------------------------------------------------------
                // Close the alert:
                //---------------------------------------------------------
                [alert.window orderOut:nil];
                
                if ([alert suppressionButton].state == NSControlStateValueOn) {
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"suppressNoLensProfileDetected"];
                }
                [self buttonLoadPresetLensProfileIsImporting:YES];
            }];
        } else {
            [self buttonLoadPresetLensProfileIsImporting:YES];
        }
    } else {
        [self showSuccessfullyImportedAlert];
    }
    
    return YES;
}

//---------------------------------------------------------
// Import Gyroflow Project with Optional URL:
//---------------------------------------------------------
- (void)importGyroflowProjectWithOptionalURL:(NSURL*)optionalURL {
    
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
            // Show error message:
            //---------------------------------------------------------
            NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource. This shouldn't happen.";
            NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
            [self showAlertWithMessage:@"An error has occurred." info:errorMessage];
            return;
        }
    }
    
    //---------------------------------------------------------
    // Load the Custom Parameter Action API:
    //---------------------------------------------------------
    id<FxCustomParameterActionAPI_v4> actionAPI = [_apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (actionAPI == nil) {
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
    
    NSString *selectedGyroflowProjectFile            = [[openPanelURL lastPathComponent] stringByDeletingPathExtension];
    NSString *selectedGyroflowProjectPath            = [openPanelURL path];
    NSString *selectedGyroflowProjectBookmarkData    = [bookmark base64EncodedStringWithOptions:0];
    
    //---------------------------------------------------------
    // Read the Gyroflow Project Data from File:
    //---------------------------------------------------------
    NSError *readError = nil;
    NSString *selectedGyroflowProjectData = [NSString stringWithContentsOfURL:openPanelURL encoding:NSUTF8StringEncoding error:&readError];
    if (readError != nil) {
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
    //NSLog(@"[Gyroflow Toolbox Renderer] hasDataResult: %@", hasDataResult);
    if (hasDataResult == nil || ![hasDataResult isEqualToString:@"YES"]) {
        NSString *errorMessage = @"The Gyroflow file you imported doesn't seem to contain any gyro data.\n\nPlease try exporting from Gyroflow again using the 'Export project file (including gyro data)' option.";
        NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
        [self showAlertWithMessage:@"Gyro Data Not Found." info:errorMessage];
        return;
    }
    
    //---------------------------------------------------------
    // Get default values from the Gyroflow Project:
    //---------------------------------------------------------
    double defaultFOV               = 1.0;
    double defaultSmoothness        = 0.5;
    double defaultLensCorrection    = 100.0;
    double defaultHorizonLock       = 0.0;
    double defaultHorizonRoll       = 0.0;
    double defaultPositionOffsetX   = 0.0;
    double defaultPositionOffsetY   = 0.0;
    double defaultVideoRotation     = 0.0;
    
    const char* getDefaultValuesResult = getDefaultValues(
        [selectedGyroflowProjectData UTF8String],
        &defaultFOV,
        &defaultSmoothness,
        &defaultLensCorrection,
        &defaultHorizonLock,
        &defaultHorizonRoll,
        &defaultPositionOffsetX,
        &defaultPositionOffsetY,
        &defaultVideoRotation
    );
    
    NSString *getDefaultValuesResultString = [NSString stringWithUTF8String:getDefaultValuesResult];
    //NSLog(@"[Gyroflow Toolbox Renderer] getDefaultValuesResult: %@", getDefaultValuesResultString);
            
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
    if ([getDefaultValuesResultString isEqualToString:@"OK"]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultFOV: %f", defaultFOV);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultSmoothness: %f", defaultSmoothness);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultLensCorrection: %f", defaultLensCorrection);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultHorizonLock: %f", defaultHorizonLock);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultHorizonRoll: %f", defaultHorizonRoll);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultPositionOffsetX: %f", defaultPositionOffsetX);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultPositionOffsetY: %f", defaultPositionOffsetY);
        //NSLog(@"[Gyroflow Toolbox Renderer] defaultVideoRotation: %f", defaultVideoRotation);
        
        [paramSetAPI setFloatValue:defaultFOV toParameter:kCB_FOV atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultSmoothness toParameter:kCB_Smoothness atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultLensCorrection toParameter:kCB_LensCorrection atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultHorizonLock toParameter:kCB_HorizonLock atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultHorizonRoll toParameter:kCB_HorizonRoll atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultPositionOffsetX toParameter:kCB_PositionOffsetX atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultPositionOffsetY toParameter:kCB_PositionOffsetY atTime:kCMTimeZero];
        [paramSetAPI setFloatValue:defaultVideoRotation toParameter:kCB_VideoRotation atTime:kCMTimeZero];
    } else {
        NSLog(@"[Gyroflow Toolbox Renderer] ERROR - Failed to get default values!");
    }
    
    //---------------------------------------------------------
    // Stop Action API:
    //---------------------------------------------------------
    [actionAPI endAction:self];
    
    //---------------------------------------------------------
    // Stop accessing security scoped resource:
    //---------------------------------------------------------
    [openPanelURL stopAccessingSecurityScopedResource];
    
    //---------------------------------------------------------
    // Show Victory Message:
    //---------------------------------------------------------
    [self showSuccessfullyImportedAlert];
}

//---------------------------------------------------------
// Import BRAW Toolbox Clip with Path:
//---------------------------------------------------------
- (void)importBRAWToolboxClipWithPath:(NSString*)path bookmarkDataString:(NSString*)bookmarkDataString {
    
    //NSLog(@"[Gyroflow Toolbox Renderer] importBRAWToolboxClipWithPath Triggered!");
    //NSLog(@"[Gyroflow Toolbox Renderer] path: %@", path);
    //NSLog(@"[Gyroflow Toolbox Renderer] bookmarkDataString: %@", bookmarkDataString);
    
    NSUserDefaults *userDefaults = [[[NSUserDefaults alloc] init] autorelease];
    NSString *brawToolboxDocumentBookmarkData = [userDefaults stringForKey:@"brawToolboxDocumentBookmarkData"];
    
    //NSLog(@"[Gyroflow Toolbox Renderer] brawToolboxDocumentBookmarkData: %@", brawToolboxDocumentBookmarkData);
    
    NSURL *urlToBRAWToolboxDocument = nil;
    
    BOOL needToRequestAccessToBRAWToolboxDocument = YES;
    
    //---------------------------------------------------------
    // Check if there's previously saved bookmark data:
    //---------------------------------------------------------
    if (brawToolboxDocumentBookmarkData != nil && ![brawToolboxDocumentBookmarkData isEqualToString:@""]) {
        
        //NSLog(@"[Gyroflow Toolbox Renderer] brawToolboxDocumentBookmarkData is valid!");
        
        //---------------------------------------------------------
        // Decode the Base64 bookmark data:
        //---------------------------------------------------------
        NSData *decodedBookmark = [[[NSData alloc] initWithBase64EncodedString:brawToolboxDocumentBookmarkData
                                                                  options:0] autorelease];

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
        // Continue if there's no error...
        //---------------------------------------------------------
        if (bookmarkError == nil || isStale == NO) {
            if ([urlToBRAWToolboxDocument startAccessingSecurityScopedResource]) {
                if ([[NSFileManager defaultManager] isReadableFileAtPath:[urlToBRAWToolboxDocument path]]) {
                    //NSLog(@"[Gyroflow Toolbox Renderer] We have access to the BRAW Toolbox Document. Yay!");
                    needToRequestAccessToBRAWToolboxDocument = NO;
                } else {
                    //NSLog(@"[Gyroflow Toolbox Renderer] We don't have access to the BRAW Toolbox Document. Yay!");
                    [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
                }
            }
        }
    }
    
    //---------------------------------------------------------
    // If we need to request access to BRAW Toolbox document:
    //---------------------------------------------------------
    if (needToRequestAccessToBRAWToolboxDocument) {
        
        //NSLog(@"[Gyroflow Toolbox Renderer] needToRequestAccessToBRAWToolboxDocument triggered!");
        
        //NSLog(@"[Gyroflow Toolbox Renderer] importMediaFileView: %@", importMediaFileView);
        //NSLog(@"[Gyroflow Toolbox Renderer] importMediaFileView.window: %@", importMediaFileView.window);
                
        //---------------------------------------------------------
        // Show an alert:
        //---------------------------------------------------------
        NSAlert *alert          = [[[NSAlert alloc] init] autorelease];
        alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = @"Gyroflow Toolbox Requires Permission";
        alert.informativeText   = @"To make it easier to import BRAW Toolbox clips into Gyroflow Toolbox, you'll need to grant Gyroflow Toolbox sandbox access to a BRAW Toolbox helper file.\n\nOn the next panel, please select 'Grant Access' to continue.";
        [alert beginSheetModalForWindow:importMediaFileView.window completionHandler:^(NSModalResponse result){
            
            //---------------------------------------------------------
            // Close the alert:
            //---------------------------------------------------------
            [alert.window orderOut:nil];
            
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
            
            //---------------------------------------------------------
            // Open the panel:
            //---------------------------------------------------------
            NSModalResponse openPanelResult = [panel runModal];
            if (openPanelResult != NSModalResponseOK) {
                return;
            }
            
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
            } else {
                NSLog(@"[Gyroflow Toolbox Renderer] We have sandbox access to: %@", [openPanelURL path]);
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
            [userDefaults setObject:base64EncodedBookmark forKey:@"brawToolboxDocumentBookmarkData"];
            
            //---------------------------------------------------------
            //
            // Lets now try and resolve the bookmark in the FCPXML:
            //
            //---------------------------------------------------------
                        
            //---------------------------------------------------------
            // Resolve the decoded bookmark data into a
            // security-scoped URL:
            //---------------------------------------------------------
            NSData *decodedBookmarkData = [[[NSData alloc] initWithBase64EncodedString:bookmarkDataString
                                                                               options:0] autorelease];
            
            NSError *brawBookmarkError  = nil;
            BOOL isStale                = NO;
            
            NSURL* brawDecodedBookmarkURL = [NSURL URLByResolvingBookmarkData:decodedBookmarkData
                                                                      options:NSURLBookmarkResolutionWithSecurityScope
                                                                relativeToURL:openPanelURL
                                                          bookmarkDataIsStale:&isStale
                                                                        error:&brawBookmarkError];
            
            //---------------------------------------------------------
            // If there was an error:
            //---------------------------------------------------------
            if (brawBookmarkError != nil) {
                NSString *errorMessage = [NSString stringWithFormat:@"Failed to resolve bookmark due to:\n\n%@", [brawBookmarkError localizedDescription]];
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                
                
                //---------------------------------------------------------
                // Stop Action API & Stop Accessing Resource:
                //---------------------------------------------------------
                [openPanelURL stopAccessingSecurityScopedResource];
                return;
            }
            
            if (![brawDecodedBookmarkURL startAccessingSecurityScopedResource]) {
                NSString *errorMessage = @"Failed to startAccessingSecurityScopedResource when attempting to access the BRAW Toolbox clip.\n\nThis shouldn't happen.";
                NSLog(@"[Gyroflow Toolbox Renderer] %@", errorMessage);
                [self showAsyncAlertWithMessage:@"An error has occurred." info:errorMessage];
                return;
            }
            
            //[self showAsyncAlertWithMessage:@"VICTORY!" info:[brawDecodedBookmarkURL path]];
                        
            //---------------------------------------------------------
            // Check to see if there's a Gyroflow project next to the
            // BRAW file:
            //---------------------------------------------------------
            NSURL *gyroflowUrl = [[brawDecodedBookmarkURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
            //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
                //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with a Gyroflow Project next to it: %@", gyroflowUrl);
                [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
            } else {
                //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with no Gyroflow Project next to it: %@", brawDecodedBookmarkURL);
                [self importMediaWithOptionalURL:brawDecodedBookmarkURL];
            }
                        
            [openPanelURL stopAccessingSecurityScopedResource];
            [brawDecodedBookmarkURL stopAccessingSecurityScopedResource];
        }];
        return;
    }
    
    //---------------------------------------------------------
    //
    // We already have access to the BRAW Toolbox document:
    //
    //---------------------------------------------------------
    
    //NSLog(@"[Gyroflow Toolbox Renderer] We already have access to: %@", urlToBRAWToolboxDocument);
    
    //---------------------------------------------------------
    // Resolve the decoded bookmark data into a
    // security-scoped URL:
    //---------------------------------------------------------
    NSData *decodedBookmarkData = [[[NSData alloc] initWithBase64EncodedString:bookmarkDataString
                                                                       options:0] autorelease];
    
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
                    
    //---------------------------------------------------------
    // Check to see if there's a Gyroflow project next to the
    // BRAW file:
    //---------------------------------------------------------
    NSURL *gyroflowUrl = [[brawDecodedBookmarkURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"gyroflow"];
    //NSLog(@"[Gyroflow Toolbox Renderer] importDroppedMedia Gyroflow URL: %@", [gyroflowUrl path]);
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[gyroflowUrl path]]) {
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with a Gyroflow Project next to it: %@", gyroflowUrl);
        [self importGyroflowProjectWithOptionalURL:gyroflowUrl];
    } else {
        //NSLog(@"[Gyroflow Toolbox Renderer] It's a Media File, with no Gyroflow Project next to it: %@", brawDecodedBookmarkURL);
        [self importMediaWithOptionalURL:brawDecodedBookmarkURL];
    }
            
    //---------------------------------------------------------
    // Stop accessing resources:
    //---------------------------------------------------------
    [brawDecodedBookmarkURL stopAccessingSecurityScopedResource];
    [urlToBRAWToolboxDocument stopAccessingSecurityScopedResource];
}

//---------------------------------------------------------
//
#pragma mark - Helpers
//
//---------------------------------------------------------

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
    
    return [result copy];
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
        NSAlert *alert          = [[[NSAlert alloc] init] autorelease];
        alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
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
        NSAlert *alert          = [[[NSAlert alloc] init] autorelease];
        alert.icon              = [NSImage imageNamed:@"GyroflowToolbox"];
        alert.alertStyle        = NSAlertStyleInformational;
        alert.messageText       = message;
        alert.informativeText   = info;
        alert.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
        [alert runModal];
    });
}

@end
