//! Portable presets and explicit defaults for newly imported media.

use crate::{BridgeError, BridgeResult, parameters, project, render};
use gyroflow_core::{StabilizationManager, lens_profile::LensProfile};
use serde_json::{Value, json};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_PRESET_BYTES: usize = 16 * 1024 * 1024;
static NEXT_WRITE: AtomicU64 = AtomicU64::new(1);

pub(crate) fn definitions() -> Vec<parameters::Parameter> {
    use parameters::{button, end_group, group, slider};
    vec![
        group(720, "Presets", true),
        button(721, "Save Preset…").symbol("kCB_SavePreset"),
        button(722, "Recall Preset").symbol("kCB_RecallPreset"),
        button(723, "Save as Default").symbol("kCB_SaveDefault"),
        button(724, "Reset Default").symbol("kCB_ResetDefault"),
        end_group(),
        group(730, "Lens Setup", true),
        slider(731, "35 mm Equivalent Focal Length", 24.0, 1.0, 2000.0, 0.1)
            .animated(false)
            .symbol("kCB_FocalLengthOnly"),
        button(732, "Use Focal Length Only").symbol("kCB_ApplyFocalLength"),
        button(733, "Restore Lens Profile").symbol("kCB_RestoreLensProfile"),
        end_group(),
    ]
}

fn directory() -> BridgeResult<PathBuf> {
    crate::resources::configured()
        .map(|paths| paths.data_directory.join("Presets"))
        .ok_or(BridgeError::InvalidInput(
            "Toolbox storage is not configured",
        ))
}

fn filename(name: &str) -> BridgeResult<String> {
    if name.trim() != name
        || name.is_empty()
        || name.chars().count() > 80
        || name.len() > 120
        || name.chars().any(char::is_control)
    {
        return Err(BridgeError::InvalidInput(
            "enter a short preset name without leading or trailing spaces",
        ));
    }
    // Encoding the entire name prevents traversal and filename collisions.
    let encoded: String = name
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    Ok(format!("{encoded}.gyroflow"))
}

fn read(path: &Path) -> BridgeResult<Value> {
    use std::io::Read;
    let mut bytes = Vec::new();
    fs::File::open(path)?
        .take((MAX_PRESET_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > MAX_PRESET_BYTES {
        return Err(BridgeError::InvalidInput("preset exceeds the size limit"));
    }
    Ok(serde_json::from_slice(&bytes)?)
}

fn write(path: &Path, document: &Value) -> BridgeResult<()> {
    let bytes = serde_json::to_vec_pretty(document)?;
    if bytes.len() > MAX_PRESET_BYTES {
        return Err(BridgeError::InvalidInput("preset exceeds the size limit"));
    }
    let directory = path
        .parent()
        .ok_or(BridgeError::InvalidInput("invalid preset path"))?;
    fs::create_dir_all(directory)?;
    let temporary = directory.join(format!(
        ".preset-{}-{}.tmp",
        std::process::id(),
        NEXT_WRITE.fetch_add(1, Ordering::Relaxed)
    ));
    let result = (|| -> std::io::Result<()> {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result?;
    Ok(())
}

/// Only explicit media import applies saved defaults; opening old effects never does.
pub(crate) fn apply_default(manager: &StabilizationManager) -> BridgeResult<()> {
    let Some(paths) = crate::resources::configured() else {
        return Ok(());
    };
    let path = paths.data_directory.join("Presets/default.gyroflow");
    match read(&path) {
        Ok(document) => project::import_into(manager, &serde_json::to_string(&document)?),
        Err(BridgeError::Io(error)) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn default_settings(source: &str, values: &str) -> BridgeResult<Value> {
    let values: Value = serde_json::from_str(values)?;
    let options = render::InspectorValues::parse(&values.to_string())?.options;
    let manager = project::import(source)?;
    crate::controls::apply(&manager, &values)?;
    // Defaults capture current scalar settings, never clip-specific animation or a lens calibration.
    manager.keyframes.write().clear();
    {
        let mut parameters = manager.params.write();
        parameters.fov = values["100"].as_f64().unwrap_or(1.0);
        parameters.lens_correction_amount = values["120"].as_f64().unwrap_or(100.0) / 100.0;
        parameters.adaptive_zoom_center_offset = (
            values["150"].as_f64().unwrap_or(0.0) / 100.0,
            values["160"].as_f64().unwrap_or(0.0) / 100.0,
        );
        if options.override_project_settings != 0 {
            parameters.max_zoom = (options.zoom_limit > 0.0).then_some(options.zoom_limit);
            parameters.additional_rotation.0 = options.additional_yaw;
            parameters.additional_rotation.1 = options.additional_pitch;
        }
    }
    manager.set_smoothing_param("smoothness", values["110"].as_f64().unwrap_or(0.5));
    {
        let mut smoothing = manager.smoothing.write();
        let horizon = &mut smoothing.horizon_lock;
        horizon.horizonlockpercent = values["130"].as_f64().unwrap_or(0.0);
        horizon.lock_enabled = horizon.horizonlockpercent > 0.0;
        horizon.horizonroll = values["140"].as_f64().unwrap_or(0.0);
    }
    if options.integration_method >= 0 {
        manager.set_integration_method(options.integration_method as usize);
    }
    let mut document =
        project::settings_from_project(&serde_json::from_str(&project::export(&manager)?)?);
    let object = document.as_object_mut().expect("preset is an object");
    for key in ["calibration_data", "keyframes", "output"] {
        object.remove(key);
    }
    if let Some(stabilization) = object
        .get_mut("stabilization")
        .and_then(Value::as_object_mut)
    {
        for key in [
            "video_rotation",
            "lens_metadata_delay_frames",
            "frame_readout_time",
            "frame_readout_direction",
            "optical_correction",
        ] {
            stabilization.remove(key);
        }
    }
    document["title"] = "Gyroflow Toolbox Default".into();
    Ok(document)
}

pub(crate) fn command(
    source: &str,
    snapshot: &str,
    values: &str,
    request: &Value,
) -> BridgeResult<Value> {
    let action = request["action"]
        .as_str()
        .ok_or(BridgeError::InvalidInput("missing preset action"))?;
    match action {
        "analysis_project" => {
            let options = render::InspectorValues::parse(values)?.options;
            let configured = render::export_project(source, snapshot, options)?;
            let manager = project::import(&configured)?;
            let parameters = manager.params.read();
            Ok(
                json!({"project": configured, "width": parameters.size.0, "height": parameters.size.1,
                "duration_ms": parameters.duration_ms, "fps": parameters.fps,
                "input_rotation": project::input_rotation(source, &manager).unwrap_or(0.0)}),
            )
        }
        "clear_optical" => {
            let manager = project::import(source)?;
            manager.clear_optical_correction();
            manager.set_ignore_file_motion(false);
            Ok(
                json!({"project": project::export_preserving_metadata(&manager, source)?, "controls": {"702": false}}),
            )
        }
        "list_presets" => {
            let directory = directory()?;
            let mut names = Vec::new();
            if directory.is_dir() {
                for entry in fs::read_dir(directory)? {
                    let path = entry?.path();
                    if path
                        .extension()
                        .is_some_and(|extension| extension == "gyroflow")
                        && path
                            .file_name()
                            .is_some_and(|name| name != "default.gyroflow")
                        && let Ok(document) = read(&path)
                        && let Some(name) = document["title"].as_str()
                    {
                        names.push(name.to_owned());
                    }
                }
            }
            names.sort();
            Ok(json!({"names": names}))
        }
        "save_default" => {
            let document = default_settings(source, values)?;
            write(&directory()?.join("default.gyroflow"), &document)?;
            Ok(json!({}))
        }
        "reset_default" => {
            match fs::remove_file(directory()?.join("default.gyroflow")) {
                Ok(()) => (),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                Err(error) => return Err(error.into()),
            }
            Ok(json!({}))
        }
        "save_preset" => {
            let name = request["name"]
                .as_str()
                .ok_or(BridgeError::InvalidInput("missing preset name"))?;
            let path = directory()?.join(filename(name)?);
            if path.exists() && request["replace"] != true {
                return Ok(json!({"exists": true}));
            }
            let options = render::InspectorValues::parse(values)?.options;
            let exported = render::export_project(source, snapshot, options)?;
            let mut document = project::settings_from_project(&serde_json::from_str(&exported)?);
            document["title"] = name.into();
            write(&path, &document)?;
            Ok(json!({}))
        }
        "apply_preset" => {
            let name = request["name"]
                .as_str()
                .ok_or(BridgeError::InvalidInput("missing preset name"))?;
            let document = read(&directory()?.join(filename(name)?))?;
            let manager = project::import(source)?;
            project::import_into(&manager, &serde_json::to_string(&document)?)?;
            Ok(json!({"project": project::export_preserving_metadata(&manager, source)?}))
        }
        "focal_length" | "restore_lens" => {
            let mut document: Value = serde_json::from_str(source)?;
            if action == "focal_length" {
                let focal_length = request["focal_length"]
                    .as_f64()
                    .filter(|value| value.is_finite() && (1.0..=2000.0).contains(value))
                    .ok_or(BridgeError::InvalidInput(
                        "invalid 35 mm equivalent focal length",
                    ))?;
                let manager = project::import(source)?;
                let size = manager.params.read().size;
                let lens = LensProfile::from_focal_length(size.0, size.1, focal_length).ok_or(
                    BridgeError::InvalidInput("load media before setting focal length"),
                )?;
                if document.get("toolbox_original_lens_profile").is_none() {
                    document["toolbox_original_lens_profile"] =
                        document["calibration_data"].clone();
                }
                document["calibration_data"] = serde_json::from_str(&lens.get_json()?)?;
            } else {
                let previous = document
                    .as_object_mut()
                    .and_then(|object| object.remove("toolbox_original_lens_profile"))
                    .ok_or(BridgeError::InvalidInput(
                        "there is no previous lens profile to restore",
                    ))?;
                document["calibration_data"] = previous;
            }
            Ok(json!({"project": serde_json::to_string(&document)?}))
        }
        _ => Err(BridgeError::InvalidInput("unknown preset action")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_cannot_escape_the_preset_directory_or_collide() {
        assert_eq!(filename("../Clip").unwrap(), "2e2e2f436c6970.gyroflow");
        assert_ne!(filename("Clip").unwrap(), filename("clip").unwrap());
        assert!(filename("\n").is_err());
        assert!(filename("").is_err());
    }

    #[test]
    fn writes_replace_complete_documents_and_leave_no_temporary_files() {
        let directory = std::env::temp_dir().join(format!(
            "gyroflow-presets-{}-{}",
            std::process::id(),
            NEXT_WRITE.fetch_add(1, Ordering::Relaxed)
        ));
        let path = directory.join("preset.gyroflow");
        write(&path, &json!({"title": "First"})).unwrap();
        write(&path, &json!({"title": "Second"})).unwrap();
        assert_eq!(read(&path).unwrap()["title"], "Second");
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        fs::remove_dir_all(directory).unwrap();
    }
    const PROJECT: &str =
        include_str!("../../../../Tests/Compatibility/Fixtures/identity.gyroflow");

    #[test]
    fn focal_length_setup_preserves_the_original_lens_across_exports() {
        let original: Value = serde_json::from_str(PROJECT).unwrap();
        let result = command(
            PROJECT,
            "",
            "",
            &json!({"action": "focal_length", "focal_length": 24.0}),
        )
        .unwrap();
        let modified = result["project"].as_str().unwrap();
        let manager = project::import(modified).unwrap();
        let exported = project::export_preserving_metadata(&manager, modified).unwrap();
        let restored = command(&exported, "", "", &json!({"action": "restore_lens"})).unwrap();
        let restored: Value = serde_json::from_str(restored["project"].as_str().unwrap()).unwrap();
        assert_eq!(restored["calibration_data"], original["calibration_data"]);
        assert!(restored.get("toolbox_original_lens_profile").is_none());
        assert!(
            command(
                PROJECT,
                "",
                "",
                &json!({"action": "focal_length", "focal_length": 0.0})
            )
            .is_err()
        );
    }

    #[test]
    fn saved_defaults_include_settings_but_not_clip_identity_lens_or_keyframes() {
        let mut values = parameters::default_values();
        values["100"] = 1.3.into();
        values["110"] = 0.72.into();
        values["130"] = 35.0.into();
        let document = default_settings(PROJECT, &values.to_string()).unwrap();
        for key in [
            "videofile",
            "video_info",
            "calibration_data",
            "keyframes",
            "offsets",
            "trim_ranges",
            "output",
        ] {
            assert!(document.get(key).is_none(), "default contains {key}");
        }
        assert_eq!(document["stabilization"]["fov"], 1.3);
        assert_eq!(document["stabilization"]["horizon_lock_amount"], 35.0);
        let manager = project::import(PROJECT).unwrap();
        project::import_into(&manager, &document.to_string()).unwrap();
        assert_eq!(manager.params.read().size, (64, 32));
        assert_eq!(manager.params.read().fov, 1.3);
        assert_eq!(
            manager
                .smoothing
                .read()
                .current()
                .get_parameter("smoothness"),
            0.72
        );
    }
}
