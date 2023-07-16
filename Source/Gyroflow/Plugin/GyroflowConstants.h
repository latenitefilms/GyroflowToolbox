//
//  GyroflowConstants.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 20/12/2022.
//

#ifndef GyroflowConstants_h
#define GyroflowConstants_h

//---------------------------------------------------------
// Plugin Parameter Constants:
//
// NOTE TO FUTURE SELF: The reason the below numbers are
//                      out of order is to retain backwards
//                      compatibility with the original
//                      Mac App Store release.
//---------------------------------------------------------
enum {
    
    
    /*
     THIS IS WHAT GOES IN THE MOTION TEMPLATE:
     
     <publishSettings>
         <version>2</version>
         <target object="10036" channel="./1" name=""/>
         <target object="10036" channel="./5" name="Import"/>
         <target object="10036" channel="./90" name="Gyroflow Parameters"/>
         <target object="10036" channel="./300" name="Tools"/>
         <target object="10036" channel="./400" name="File Management"/>
     </publishSettings>
     */
    
    //---------------------------------------------------------
    // Top Section:
    //---------------------------------------------------------
    kCB_TopSection                              = 1,
        kCB_Header                              = 2,
        kCB_OpenUserGuide                       = 3,
    
    //---------------------------------------------------------
    // Import Section:
    //---------------------------------------------------------
    kCB_ImportSection                           = 5,
    
        kCB_DropZone                            = 10,
        kCB_ImportGyroflowProject               = 30,
        kCB_LoadLastGyroflowProject             = 25,
        kCB_ImportMediaFile                     = 35,
        kCB_LoadPresetLensProfile               = 52,
    
    //---------------------------------------------------------
    // Parameters:
    //---------------------------------------------------------
    kCB_GyroflowParameters                      = 90,
    
        kCB_FOV                                 = 100,
        kCB_Smoothness                          = 110,
        kCB_LensCorrection                      = 120,
            
        kCB_HorizonLock                         = 130,
        kCB_HorizonRoll                         = 140,
            
        kCB_PositionOffsetX                     = 150,
        kCB_PositionOffsetY                     = 160,
        kCB_InputRotation                       = 170,
        kCB_VideoRotation                       = 180,
        kCB_VideoSpeed                          = 190,
    
    //---------------------------------------------------------
    // Tools:
    //---------------------------------------------------------
    kCB_ToolsSection                            = 300,
    
        kCB_FieldOfViewOverview                 = 310,
        kCB_DisableGyroflowStretch              = 320,
    
    //---------------------------------------------------------
    // File Management:
    //---------------------------------------------------------
    kCB_FileManagementSection                   = 400,
    
        kCB_LoadedGyroflowProject               = 40,
        kCB_ReloadGyroflowProject               = 50,
        kCB_LaunchGyroflow                      = 20,
        kCB_ExportGyroflowProject               = 51,
        kCB_RevealInFinder                      = 55,
    
    //---------------------------------------------------------
    // Hidden Metadata:
    //---------------------------------------------------------
    kCB_UniqueIdentifier                        = 500,
    kCB_GyroflowProjectPath                     = 60,
    kCB_GyroflowProjectBookmarkData             = 70,
    kCB_GyroflowProjectData                     = 80,
};

//---------------------------------------------------------
// Plugin Error Codes:
//
// All 3rd party error values should be >= 100000 if
// none of the above error enum values are sufficient.
//---------------------------------------------------------
enum {
    kFxError_FailedToLoadTimingAPI = 100010,                    // Failed to load FxTimingAPI_v4
    kFxError_FailedToLoadParameterGetAPI,                       // Failed to load FxParameterRetrievalAPI_v6
    kFxError_PlugInStateIsNil,                                  // Plugin State is `nil`
    kFxError_UnsupportedPixelFormat,                            // Unsupported Pixel Format
    kFxError_FailedToCreatePluginState,                         // Failed to create plugin state
    kFxError_CommandQueueWasNilDuringShowErrorMessage           // Command Queue was `nil` during a show error message render.
};

#endif /* GyroflowConstants_h */
