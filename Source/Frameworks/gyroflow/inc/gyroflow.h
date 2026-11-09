//
//  gyroflow.h
//  Gyroflow Toolbox
//
//  Created by Chris Hocking on 11/12/2022.
//

#ifndef GYROFLOW_TOOLBOX_H
#define GYROFLOW_TOOLBOX_H

#include <stdint.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

// Owned JSON; release using freeCString. Does not mutate the imported project.
const char *getEngineControlDefaults(const char *data);
const char *getParameterConstants(void);

/** Version 1 render options. Zero reserved fields; initialize using getRenderDefaults. */
typedef struct GyroflowRenderOptions {
    uint32_t version;
    uint32_t override_project_settings;
    double zoom_limit;
    double additional_pitch;
    double additional_yaw;
    int32_t integration_method;
    uint32_t interpolation;
    uint32_t use_project_keyframes;
    uint32_t reserved;
} GyroflowRenderOptions;

int getOptionsFromParameters(const char *parameters, GyroflowRenderOptions *options);
int processFrameWithParameters(const char *identifier, uint32_t width, uint32_t height, const char *format,
    int component_bytes, const char *path, const char *data, int64_t timestamp, const char *parameters,
    const char *keyframes, void *input_texture, void *output_texture, void *command_queue);

// Owned project with current inspector curves; release using freeCString.
const char *exportConfiguredProject(const char *data, const char *snapshot, const GyroflowRenderOptions *options);

/** Writes legacy-compatible defaults. Returns 1 on success. */
int getRenderDefaults(GyroflowRenderOptions *options);

/** Owned JSON inspector descriptors; release with freeCString. */
const char *getPluginParameterDefinitions(void);

/** Host animation is sampled synchronously; the callback and context are never retained. */
typedef int (*GyroflowSampleParameter)(void *context, uint32_t parameter, int64_t timestamp, double *value);
const char *getKeyframeParameterIDs(void);
const char *buildHostKeyframes(const char *project, const char *signature,
                              void *context, GyroflowSampleParameter sample);

/** Reads advanced project defaults. Returns 1 on success; output is unchanged on failure. */
int getAdvancedDefaults(const char *data, GyroflowRenderOptions *options);

//---------------------------------------------------------
// Start the logger:
//---------------------------------------------------------
void startLogger(
    const char*                 log_file_path
);

//---------------------------------------------------------
// Process a frame:
//---------------------------------------------------------
int processFrame(
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
// Is a lens profile loaded in the Gyroflow Project?
//---------------------------------------------------------
const char* isLensProfileLoaded(
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

//---------------------------------------------------------
// Gets the Lens Identifier:
//---------------------------------------------------------
const char* getLensIdentifier(
    const char*                 gyroflow_project_data
);

//---------------------------------------------------------
// Free C String:
//---------------------------------------------------------
void freeCString(char *s);

/** Versioned frame interface. Null options preserve the processFrame behavior. */
int processFrameV2(
    const char *unique_identifier, uint32_t width, uint32_t height,
    const char *pixel_format, int number_of_bytes, const char *path, const char *data,
    int64_t timestamp, double fov, double smoothness, double lens_correction,
    double horizon_lock, double horizon_roll, double position_offset_x,
    double position_offset_y, double input_rotation, double video_rotation,
    uint8_t fov_overview, uint8_t disable_gyroflow_stretch,
    void *in_mtl_texture, void *out_mtl_texture, void *command_queue,
    const GyroflowRenderOptions *options
);

/** Renders with the Core keyframe provider and a portable host-animation snapshot. */
int processFrameWithKeyframes(
    const char *unique_identifier, uint32_t width, uint32_t height,
    const char *pixel_format, int number_of_bytes, const char *path, const char *data,
    int64_t timestamp, double fov, double smoothness, double lens_correction,
    double horizon_lock, double horizon_roll, double position_offset_x,
    double position_offset_y, double input_rotation, double video_rotation,
    uint8_t fov_overview, uint8_t disable_gyroflow_stretch,
    void *in_mtl_texture, void *out_mtl_texture, void *command_queue,
    const GyroflowRenderOptions *options, const char *host_keyframes
);

#ifdef __cplusplus
}
#endif
#endif
