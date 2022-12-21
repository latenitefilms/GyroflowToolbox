//
//  GyroflowConstants.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 20/12/2022.
//

#ifndef GyroflowConstants_h
#define GyroflowConstants_h

//---------------------------------------------------------
// Plugin Parameter Constants:
//---------------------------------------------------------
enum {
    kCB_GyroflowProject                 = 10,
    kCB_LaunchGyroflow                  = 20,
    kCB_ImportGyroflowProject           = 30,
    kCB_LoadedGyroflowProject           = 40,
    kCB_ReloadGyroflowProject           = 50,
    
    kCB_GyroflowProjectPath             = 60,
    kCB_GyroflowProjectBookmarkData     = 70,
    kCB_GyroflowProjectData             = 80,
      
    kCB_GyroflowParameters              = 90,
    kCB_FOV                             = 100,
    kCB_Smoothness                      = 110,
    kCB_LensCorrection                  = 120,
};

//---------------------------------------------------------
// Plugin Error Codes:
//
// All 3rd party error values should be >= 100000 if
// none of the above error enum values are sufficient.
//---------------------------------------------------------
enum {
    kFxError_FailedToLoadTimingAPI = 100010,    // Failed to load FxTimingAPI_v4
    kFxError_FailedToLoadParameterGetAPI,       // Failed to load FxParameterRetrievalAPI_v6
    kFxError_PlugInStateIsNil,                  // Plugin State is `nil`
    kFxError_UnsupportedPixelFormat,            // Unsupported Pixel Format
    kFxError_FailedToCreatePluginState          // Failed to create plugin state
};

#endif /* GyroflowConstants_h */
