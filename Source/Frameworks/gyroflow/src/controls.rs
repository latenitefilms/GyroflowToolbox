//! Additional Core controls, described and applied in Rust; FxPlug only transports values.

use crate::{BridgeError, BridgeResult};
use gyroflow_core::{StabilizationManager, keyframes::KeyframeType};
use serde_json::{Value, json};

/// Numeric controls that participate in Core's immutable animation provider.
pub(crate) const KEYFRAMES: [(u32, KeyframeType, f64); 8] = [
    (612, KeyframeType::ZoomingSpeed, 1.0),
    (614, KeyframeType::AdditionalRotationZ, 1.0),
    (615, KeyframeType::AdditionalTranslationX, 1.0),
    (616, KeyframeType::AdditionalTranslationY, 1.0),
    (617, KeyframeType::AdditionalTranslationZ, 1.0),
    (621, KeyframeType::LockHorizonPitch, 1.0),
    (636, KeyframeType::LightRefractionCoeff, 1.0),
    (645, KeyframeType::BackgroundMargin, 100.0),
];

fn slider(
    id: u32,
    name: &'static str,
    default: f64,
    min: f64,
    max: f64,
    delta: f64,
) -> crate::parameters::Parameter {
    crate::parameters::slider(id, name, default, min, max, delta)
        .animated(KEYFRAMES.iter().any(|(identifier, _, _)| *identifier == id))
}
use crate::parameters::{Parameter, end_group, group, menu, toggle};

pub(crate) fn definitions() -> Vec<Parameter> {
    vec![
        group(600, "Advanced Stabilisation", true),
        toggle(601, "Override Advanced Project Settings", false),
        menu(
            610,
            "Smoothing Method",
            0,
            &[
                "Default",
                "Optimal Path",
                "Plain 3D",
                "Fixed Camera",
                "None",
            ],
        ),
        menu(
            611,
            "Zoom Mode",
            0,
            &["Dynamic", "Static", "Fixed at Zoom Limit", "None"],
        ),
        slider(612, "Zooming Speed (s)", 4.0, 0.1, 20.0, 0.1),
        slider(613, "Zoom Limit Iterations", 5.0, 1.0, 10.0, 1.0),
        slider(614, "Additional Roll", 0.0, -180.0, 180.0, 0.1),
        slider(615, "3D Translation X", 0.0, -2000.0, 2000.0, 1.0),
        slider(616, "3D Translation Y", 0.0, -2000.0, 2000.0, 1.0),
        slider(617, "3D Translation Z", 0.0, -2000.0, 2000.0, 1.0),
        toggle(620, "Lock Horizon Pitch", false),
        slider(621, "Horizon Pitch", 0.0, -90.0, 90.0, 0.1),
        toggle(622, "Automatic Horizon Lock", false),
        slider(623, "Horizon Turn Threshold", 5.0, 0.0, 180.0, 0.1),
        slider(624, "Horizon Response (ms)", 500.0, 1.0, 5000.0, 1.0),
        slider(625, "Horizon Turn Multiplier", 1.0, 0.0, 4.0, 0.01),
        toggle(626, "Use Gravity Vectors", true),
        toggle(630, "Stabilise Focal Length", false),
        slider(631, "Focal Length Zoom Rate", 0.5, 0.01, 10.0, 0.01),
        toggle(632, "Lens Breathing Compensation", true),
        slider(633, "Lens Metadata Delay (frames)", 0.0, -30.0, 30.0, 1.0),
        slider(634, "Rolling Shutter Readout (ms)", 0.0, 0.0, 100.0, 0.01),
        menu(
            635,
            "Readout Direction",
            0,
            &[
                "Top to Bottom",
                "Bottom to Top",
                "Left to Right",
                "Right to Left",
            ],
        ),
        slider(636, "Light Refraction Coefficient", 1.0, 0.5, 2.0, 0.001),
        menu(
            637,
            "Output Projection",
            1,
            &[
                "Automatic",
                "Rectilinear",
                "Stereographic",
                "Equidistant",
                "Equisolid Angle",
                "Orthographic",
            ],
        ),
        slider(
            640,
            "Additional Sync Offset (ms)",
            0.0,
            -10000.0,
            10000.0,
            0.1,
        ),
        slider(641, "Motion Low-Pass Filter (Hz)", 0.0, 0.0, 500.0, 0.1),
        slider(642, "Motion Median Filter", 0.0, 0.0, 100.0, 1.0),
        toggle(643, "Use Saved Optical Correction", true),
        menu(
            644,
            "Frame Edges",
            0,
            &[
                "Transparent",
                "Repeat Pixels",
                "Mirror Pixels",
                "Margin with Feather",
            ],
        ),
        slider(645, "Background Margin (%)", 0.0, 0.0, 100.0, 0.1),
        slider(646, "Background Feather (%)", 0.0, 0.0, 100.0, 0.1),
        end_group(),
    ]
}

pub(crate) fn enabled(values: &Value) -> bool {
    values["601"].as_bool() == Some(true)
}

/// Returns the current project values, including explicit defaults for newly added controls.
pub(crate) fn defaults(manager: &StabilizationManager) -> Value {
    let parameters = manager.params.read();
    let smoothing = manager.smoothing.read();
    let horizon = &smoothing.horizon_lock;
    let gyro = manager.gyro.read();
    let smoothing_index = smoothing
        .get_names()
        .iter()
        .position(|name| *name == smoothing.current().get_name())
        .unwrap_or(1);
    let menu_index = [1, 2, 3, 4, 0]
        .iter()
        .position(|index| *index == smoothing_index)
        .unwrap_or(0);
    let zoom_mode = if parameters.fixed_zoom {
        2
    } else if parameters.adaptive_zoom_window < 0.0 {
        1
    } else if parameters.adaptive_zoom_window == 0.0 {
        3
    } else {
        0
    };
    let mut values = json!({
        "100": parameters.fov, "110": smoothing.current().get_parameter("smoothness"),
        "120": parameters.lens_correction_amount * 100.0,
        "130": if horizon.lock_enabled { horizon.horizonlockpercent } else { 0.0 },
        "140": horizon.horizonroll, "150": parameters.adaptive_zoom_center_offset.0 * 100.0,
        "160": parameters.adaptive_zoom_center_offset.1 * 100.0, "180": parameters.video_rotation,
        "210": parameters.max_zoom.unwrap_or(0.0), "220": parameters.additional_rotation.1,
        "230": parameters.additional_rotation.0,
        "200": false, "240": 0, "250": 0, "260": true,
    });
    let advanced = json!({
        "601": false, "610": menu_index, "611": zoom_mode,
        "612": if parameters.adaptive_zoom_window > 0.0 { parameters.adaptive_zoom_window } else { 4.0 },
        "613": parameters.max_zoom_iterations, "614": parameters.additional_rotation.2,
        "615": parameters.additional_translation.0, "616": parameters.additional_translation.1, "617": parameters.additional_translation.2,
        "620": horizon.lock_pitch, "621": horizon.horizonpitch, "622": horizon.automatic_lock,
        "623": horizon.turn_threshold, "624": horizon.turn_smoothing_ms, "625": horizon.turn_multiplier,
        "626": gyro.use_gravity_vectors, "630": parameters.focal_length_smoothing_enabled,
        "631": parameters.focal_length_max_zoom_rate, "632": parameters.lens_breathing_enabled,
        "633": parameters.lens_metadata_delay_frames, "634": parameters.frame_readout_time.abs(),
        "635": parameters.frame_readout_direction as i32, "636": parameters.light_refraction_coefficient,
        "637": parameters.output_projection + 1, "640": 0.0,
        "641": gyro.imu_transforms.imu_lpf, "642": gyro.imu_transforms.imu_mf,
        "643": gyro.optical_correction.as_ref().is_none_or(|correction| correction.enabled),
        "644": parameters.background_mode as i32,
        "645": parameters.background_margin * 100.0, "646": parameters.background_margin_feather * 100.0,
        "701": if manager.optical_tracking.read().name() == "gmflow" { 1 } else { 0 },
        "702": gyro.ignores_file_motion(),
        "703": manager.optical_settings.read().strength * 100.0,
        "704": manager.optical_settings.read().per_frame,
    });
    values
        .as_object_mut()
        .expect("defaults are an object")
        .extend(
            advanced
                .as_object()
                .expect("advanced defaults are an object")
                .clone(),
        );
    values
}

/// Validates the entire payload before mutating an engine. Values are untrusted render-state data.
pub(crate) fn validate(values: &Value) -> BridgeResult<()> {
    if values.is_null() {
        return Ok(());
    }
    if !values.is_object() {
        return Err(BridgeError::InvalidInput("invalid advanced settings"));
    }
    if values["601"].as_bool() == Some(false) {
        return Ok(());
    }
    for parameter in definitions() {
        parameter.validate_value(values)?;
    }
    Ok(())
}

/// Applied once to a newly imported project, before attaching its animation provider.
pub(crate) fn apply(manager: &StabilizationManager, values: &Value) -> BridgeResult<()> {
    validate(values)?;
    if !enabled(values) {
        return Ok(());
    }
    let number = |id: u32| {
        values[id.to_string()]
            .as_f64()
            .expect("settings validated above")
    };
    let flag = |id: u32| {
        values[id.to_string()]
            .as_bool()
            .expect("settings validated above")
    };
    {
        let mut parameters = manager.params.write();
        parameters.adaptive_zoom_window = match number(611) as u32 {
            1 | 2 => -1.0,
            3 => 0.0,
            _ => number(612),
        };
        parameters.fixed_zoom = number(611) == 2.0;
        parameters.max_zoom_iterations = number(613).round() as usize;
        parameters.additional_rotation.2 = number(614);
        parameters.additional_translation = (number(615), number(616), number(617));
        parameters.focal_length_smoothing_enabled = flag(630);
        parameters.focal_length_max_zoom_rate = number(631);
        parameters.lens_breathing_enabled = flag(632);
        parameters.lens_metadata_delay_frames = number(633).round() as i32;
        parameters.frame_readout_time = number(634);
        parameters.frame_readout_direction = (number(635) as i32).into();
        parameters.light_refraction_coefficient = number(636);
        parameters.output_projection = number(637) as i32 - 1;
        parameters.background_mode = (number(644) as i32).into();
        parameters.background_margin = number(645) / 100.0;
        parameters.background_margin_feather = number(646) / 100.0;
    }
    {
        let mut smoothing = manager.smoothing.write();
        smoothing.set_current([1, 2, 3, 4, 0][number(610) as usize]);
        let horizon = &mut smoothing.horizon_lock;
        horizon.lock_pitch = flag(620);
        horizon.horizonpitch = number(621);
        horizon.automatic_lock = flag(622);
        horizon.turn_threshold = number(623);
        horizon.turn_smoothing_ms = number(624);
        horizon.turn_multiplier = number(625);
    }
    {
        let mut gyro = manager.gyro.write();
        let offset = number(640);
        if offset != 0.0 {
            let mut offsets = gyro.get_offsets().clone();
            if offsets.is_empty() {
                offsets.insert(0, offset);
            } else {
                for value in offsets.values_mut() {
                    *value += offset;
                }
            }
            gyro.set_offsets(offsets);
        }
        gyro.use_gravity_vectors = flag(626);
        gyro.imu_transforms.imu_lpf = number(641);
        gyro.imu_transforms.imu_mf = number(642).round() as i32;
    }
    manager.set_optical_correction_enabled(flag(643));
    manager.recompute_gyro();
    manager.invalidate_blocking_smoothing();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn controls_preserve_projects_until_enabled_and_apply_engine_features() {
        let manager = StabilizationManager::default();
        let mut values = defaults(&manager);
        values["610"] = 1.into();
        values["630"] = true.into();
        apply(&manager, &values).unwrap();
        assert_eq!(manager.smoothing.read().current().get_name(), "Default");
        assert!(!manager.params.read().focal_length_smoothing_enabled);
        values["601"] = true.into();
        values["640"] = 12.5.into();
        values["633"] = 2.into();
        values["622"] = true.into();
        manager.gyro.write().set_offset(1000, 3.0);
        apply(&manager, &values).unwrap();
        assert_eq!(
            manager.smoothing.read().current().get_name(),
            "Optimal path"
        );
        assert!(manager.params.read().focal_length_smoothing_enabled);
        assert_eq!(manager.params.read().lens_metadata_delay_frames, 2);
        assert!(manager.smoothing.read().horizon_lock.automatic_lock);
        assert_eq!(manager.gyro.read().get_offsets().get(&1000), Some(&15.5));
    }
    #[test]
    fn malformed_controls_fail_before_mutating_the_engine() {
        let manager = StabilizationManager::default();
        let mut values = defaults(&manager);
        values["601"] = true.into();
        values["610"] = 1.into();
        values["636"] = (-1).into();
        assert!(apply(&manager, &values).is_err());
        assert_eq!(manager.smoothing.read().current().get_name(), "Default");
        values.as_object_mut().unwrap().remove("636");
        assert!(validate(&values).is_err());
    }
}
