//
//  GyroflowConstants.h
//  Gyroflow Toolbox Renderer
//
//  Created by Chris Hocking on 20/12/2022.
//

#ifndef GyroflowConstants_h
#define GyroflowConstants_h

// Stable parameter identifiers are generated from the Rust catalog.
#include "gyroflow_parameters.h"

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
    kFxError_CommandQueueWasNilDuringShowErrorMessage,          // Command Queue was `nil` during a show error message render.

    //---------------------------------------------------------
    // Error Messages:
    //---------------------------------------------------------
    kFxError_AssetLoadFailed,                                   // Failed to load error message asset
    kFxError_ImageCreationFailed,                               // Failed to create image for error messages
    kFxError_CIContextCreationFailed,                           // Failed to create Core Image context for error messages
    kFxError_IOSurfaceCreationFailed,                           // Failed to create IOSurface for error messages
    kFxError_MetalDeviceNotFound,                               // Failed to get Metal Device for error messages
    kFxError_CommandBufferCreationFailed,                       // Failed to create Command Buffer for error messages
};

#endif /* GyroflowConstants_h */
