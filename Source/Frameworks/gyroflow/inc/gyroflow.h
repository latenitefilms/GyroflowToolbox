//
//  gyroflow.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 11/12/2022.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//---------------------------------------------------------
// Process a frame:
//---------------------------------------------------------
const char* processFrame(
    const char*                 unique_identifier,
    uint32_t                    width,
    uint32_t                    height,
    const char*                 pixel_format,
    int                         number_of_bytes,
    const char*                 path,
    const char*                 data,
    int64_t                     timestamp,
    double                      fov,
    double                      smoothness,
    double                      lens_correction,
    double                      horizon_lock,
    double                      horizon_roll,
    double                      position_offset_x,
    double                      position_offset_y,
    double                      input_rotation,
    double                      video_rotation,
    uint8_t                     fov_overview,
    uint8_t                     disable_gyroflow_stretch,
    void                        *in_mtl_texture,
    void                        *out_mtl_texture,
    void                        *command_queue
);

//---------------------------------------------------------
// Get default values from a Gyroflow Project:
//---------------------------------------------------------
const char* getDefaultValues(
    const char* gyroflow_project_data,
    double* fov,
    double* smoothness,
    double* lens_correction,
    double* horizon_lock,
    double* horizon_roll,
    double* position_offset_x,
    double* position_offset_y,
    double* video_rotation
);

//---------------------------------------------------------
// Trash the gyroflow_core cache:
//---------------------------------------------------------
uint32_t trashCache(
    void
);

//---------------------------------------------------------
// Import Media File:
//---------------------------------------------------------
const char* importMediaFile(
    const char*                 media_file_path
);

//---------------------------------------------------------
// Does the Gyroflow Project contain Stabilisation Data?
//---------------------------------------------------------
const char* doesGyroflowProjectContainStabilisationData(
    const char*                 gyroflow_project_data
);

//---------------------------------------------------------
// Does the Gyroflow Project have accurate timestamps?
//---------------------------------------------------------
const char* hasAccurateTimestamps(
    const char*                 gyroflow_project_data
);

//---------------------------------------------------------
// Is an official lens loaded in the Gyroflow Project?
//---------------------------------------------------------
const char* isOfficialLensLoaded(
    const char*                 gyroflow_project_data
);

//---------------------------------------------------------
// Load a Lens Profile into a Gyroflow Project:
//---------------------------------------------------------
const char* loadLensProfile(
    const char*                 gyroflow_project_data,
    const char*                 lens_profile_path
);

//---------------------------------------------------------
// Load a Preset into a Gyroflow Project:
//---------------------------------------------------------
const char* loadPreset(
    const char*                 gyroflow_project_data,
    const char*                 lens_profile_path
);
