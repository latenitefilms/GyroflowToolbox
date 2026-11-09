//! Project import, inspection caching, and preset isolation.
use crate::{BridgeError, BridgeResult, cache::Cache, new_manager};
use gyroflow_core::{GyroflowProjectType, StabilizationManager};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::num::NonZeroUsize;
use std::sync::{Arc, LazyLock, atomic::AtomicBool};

struct InspectedProject {
    source: String,
    manager: StabilizationManager,
}
static INSPECTION_CACHE: LazyLock<Cache<u64, InspectedProject>> = LazyLock::new(|| {
    Cache::new(NonZeroUsize::new(2).expect("inspection cache capacity is nonzero"))
});

pub(crate) fn fingerprint(data: &str) -> u64 {
    let mut hasher = DefaultHasher::new();
    data.hash(&mut hasher);
    hasher.finish()
}

pub(crate) fn inspect<Value>(
    data: &str,
    inspect: impl FnOnce(&StabilizationManager) -> Value,
) -> BridgeResult<Value> {
    let slot = INSPECTION_CACHE.slot(fingerprint(data));
    let mut cached = slot.lock().expect("project inspection mutex poisoned");
    // Compare the source too, so hash collisions cannot select a different project's telemetry.
    if cached.as_ref().is_none_or(|project| project.source != data) {
        *cached = Some(InspectedProject {
            manager: import(data)?,
            source: data.to_owned(),
        });
    }
    Ok(inspect(
        &cached.as_ref().expect("project initialized above").manager,
    ))
}

pub(crate) fn clear_cache() {
    INSPECTION_CACHE.clear();
}

pub(crate) fn import(data: &str) -> BridgeResult<StabilizationManager> {
    let manager = new_manager();
    import_into(&manager, data)?;
    Ok(manager)
}

pub(crate) fn import_into(manager: &StabilizationManager, data: &str) -> BridgeResult<()> {
    let value: serde_json::Value = serde_json::from_str(data)?;
    if !value.is_object() {
        return Err(BridgeError::InvalidInput("project must be a JSON object"));
    }
    manager.import_gyroflow_data(
        data.as_bytes(),
        true,
        None,
        |_| (),
        Arc::new(AtomicBool::new(false)),
        &mut false,
        true,
    )?;
    Ok(())
}

pub(crate) fn export(manager: &StabilizationManager) -> BridgeResult<String> {
    Ok(manager.export_gyroflow_data(GyroflowProjectType::WithGyroData, "{}", None)?)
}

/// Rotation metadata describes the host's input pixels, independently of the output rotation.
pub(crate) fn input_rotation(data: &str, manager: &StabilizationManager) -> Option<f64> {
    let value: serde_json::Value = serde_json::from_str(data).ok()?;
    if let Some(rotation) = value["toolbox_input_rotation"]
        .as_f64()
        .filter(|v| v.is_finite())
    {
        return Some(rotation);
    }
    let url = manager.input_file.read().url.clone();
    // The host holds any required security scope during import. An offline original
    // simply leaves the existing manual Input Rotation control available.
    let mut file = gyroflow_core::filesystem::open_file(&url, false, false).ok()?;
    let size = file.size;
    let metadata = gyroflow_core::util::get_video_metadata(file.get_file(), size, &url).ok()?;
    Some(rotation_from_metadata(metadata.rotation))
}

pub(crate) fn rotation_from_metadata(rotation: i32) -> f64 {
    ((360 - rotation.rem_euclid(360)) % 360) as f64
}

pub(crate) fn export_preserving_metadata(
    manager: &StabilizationManager,
    source: &str,
) -> BridgeResult<String> {
    let mut document: serde_json::Value = serde_json::from_str(&export(manager)?)?;
    if let Some(rotation) = input_rotation(source, manager) {
        document["toolbox_input_rotation"] = rotation.into();
    }
    let original: serde_json::Value = serde_json::from_str(source)?;
    if let Some(value) = original.get("toolbox_original_lens_profile") {
        document["toolbox_original_lens_profile"] = value.clone();
    }
    Ok(serde_json::to_string(&document)?)
}

pub(crate) fn read_preset(path_or_json: &str) -> BridgeResult<String> {
    let data = if path_or_json.trim_start().starts_with('{') {
        path_or_json.to_owned()
    } else {
        std::fs::read_to_string(path_or_json)?
    };
    let mut document: serde_json::Value = serde_json::from_str(&data)?;
    if !document.is_object() {
        return Err(BridgeError::InvalidInput("preset must be a JSON object"));
    }
    // A .gyroflow project selected as a preset contributes settings, never another clip's
    // filename, gyro samples, synchronization offsets, or trim. Matches the official plugins.
    if document.get("videofile").is_some() {
        document = settings_from_project(&document);
    }
    Ok(serde_json::to_string(&document)?)
}

pub(crate) fn settings_from_project(document: &serde_json::Value) -> serde_json::Value {
    let mut preset = serde_json::Map::new();
    for key in [
        "version",
        "calibration_data",
        "light_refraction_coefficient",
        "plugin_disable_stretch",
        "keyframes",
        "background_color",
        "background_mode",
        "background_margin",
        "background_margin_feather",
        "stabilization",
    ] {
        if let Some(value) = document.get(key) {
            preset.insert(key.into(), value.clone());
        }
    }
    for (group, keys) in [
        (
            "gyro_source",
            &[
                "lpf",
                "mf",
                "rotation",
                "acc_rotation",
                "gyro_bias",
                "imu_orientation",
                "integration_method",
            ][..],
        ),
        (
            "output",
            &["output_width", "output_height", "interpolation"][..],
        ),
    ] {
        let values: serde_json::Map<String, serde_json::Value> = keys
            .iter()
            .filter_map(|key| {
                document
                    .get(group)?
                    .get(*key)
                    .map(|value| ((*key).into(), value.clone()))
            })
            .collect();
        if !values.is_empty() {
            preset.insert(group.into(), values.into());
        }
    }
    preset.insert("name".into(), "Project settings".into());
    preset.into()
}
