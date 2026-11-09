//! Host curve sampling into the same native keyframe engine used by the official plugins.
//!
//! FxPlug supplies evaluated curve samples only when the curve signature changes.
//! Rendering never calls the host: it reads an immutable, portable snapshot in Core.

use crate::{BridgeError, BridgeResult, cache::Cache, controls, project};
use gyroflow_core::{
    StabilizationManager,
    keyframes::{Easing, Keyframe, KeyframeManager, KeyframeType},
};
use serde_json::Value;
use std::collections::BTreeMap;
use std::num::NonZeroUsize;
use std::sync::LazyLock;

/// Bound host-generated animation data before allocating Core's keyframe maps.
const MAX_SAMPLES: usize = 1_000_000;
const MAX_SNAPSHOT_BYTES: usize = 64 * 1024 * 1024;
type Samples = Vec<(u32, Vec<(i64, f64)>)>;
fn parameters() -> impl Iterator<Item = (u32, KeyframeType, f64)> {
    crate::parameters::keyframed()
}

struct Snapshot {
    signature: String,
    encoded: String,
}
static SNAPSHOTS: LazyLock<Cache<(u64, u64), Snapshot>> = LazyLock::new(|| {
    Cache::new(NonZeroUsize::new(8).expect("animation cache capacity is nonzero"))
});

pub(crate) fn parameter_ids() -> Value {
    Value::Array(
        parameters()
            .map(|(identifier, _, _)| identifier.into())
            .collect(),
    )
}
pub(crate) fn clear_cache() {
    SNAPSHOTS.clear();
}

pub(crate) fn snapshot(
    project_data: &str,
    signature: &str,
    mut sample: impl FnMut(u32, i64) -> BridgeResult<f64>,
) -> BridgeResult<String> {
    if signature.len() > MAX_SNAPSHOT_BYTES {
        return Err(BridgeError::InvalidInput(
            "animation signature exceeds the memory budget",
        ));
    }
    let slot = SNAPSHOTS.slot((
        project::fingerprint(signature),
        project::fingerprint(project_data),
    ));
    let mut cached = slot.lock().expect("animation snapshot mutex poisoned");
    if let Some(snapshot) = cached
        .as_ref()
        .filter(|snapshot| snapshot.signature == signature)
    {
        return Ok(snapshot.encoded.clone());
    }
    // Duration is only needed after an edit. Do not import or integrate a project
    // just to render another frame with the same curves.
    let document: Value = serde_json::from_str(project_data)?;
    let duration_ms = document["video_info"]["duration_ms"]
        .as_f64()
        .unwrap_or(0.0);
    if !duration_ms.is_finite() || duration_ms < 0.0 {
        return Err(BridgeError::InvalidInput("invalid animation duration"));
    }
    let metadata: Value = serde_json::from_str(signature)?;
    let fps = metadata["fps"]
        .as_f64()
        .ok_or(BridgeError::InvalidInput("missing animation frame rate"))?;
    if !fps.is_finite() || !(0.0..=1000.0).contains(&fps) || fps == 0.0 {
        return Err(BridgeError::InvalidInput("invalid animation frame rate"));
    }
    let host_parameters = metadata["parameters"]
        .as_array()
        .ok_or(BridgeError::InvalidInput("missing animation parameters"))?;
    let last_frame = (duration_ms / 1000.0 * fps).ceil() as i64;
    let mut total_samples = 0_usize;
    let mut rows = Vec::with_capacity(parameters().count());
    for (identifier, _, _) in parameters() {
        let parameter = host_parameters
            .iter()
            .find(|value| value["id"].as_u64() == Some(u64::from(identifier)))
            .ok_or(BridgeError::InvalidInput(
                "incomplete host animation snapshot",
            ))?;
        let keys = parameter["keys"]
            .as_array()
            .ok_or(BridgeError::InvalidInput("missing host keyframes"))?;
        if keys.len() > MAX_SAMPLES.saturating_sub(total_samples) {
            return Err(BridgeError::InvalidInput("too many host keyframes"));
        }
        let mut timestamps = Vec::new();
        if keys.len() > 1 {
            let times: Vec<i64> = keys
                .iter()
                .map(|key| {
                    key["time_us"]
                        .as_i64()
                        .ok_or(BridgeError::InvalidInput("invalid keyframe time"))
                })
                .collect::<BridgeResult<_>>()?;
            let first = times.iter().min().copied().unwrap_or(0);
            let last = times.iter().max().copied().unwrap_or(0);
            let start = ((first as f64 / 1_000_000.0 * fps).floor() as i64).clamp(0, last_frame);
            let end = ((last as f64 / 1_000_000.0 * fps).ceil() as i64).clamp(start, last_frame);
            let frame_count = (end - start)
                .checked_add(1)
                .ok_or(BridgeError::InvalidInput("animation is too long"))?;
            let count = usize::try_from(frame_count)
                .map_err(|_| BridgeError::InvalidInput("animation is too long"))?;
            if count
                > MAX_SAMPLES
                    .saturating_sub(total_samples)
                    .saturating_sub(keys.len())
            {
                return Err(BridgeError::InvalidInput(
                    "animation exceeds the sample memory budget",
                ));
            }
            timestamps.extend(
                (start..=end).map(|frame| (frame as f64 / fps * 1_000_000.0).round() as i64),
            );
            timestamps.extend(
                times
                    .into_iter()
                    .filter(|time| *time >= 0 && (*time as f64) <= duration_ms * 1000.0),
            );
            timestamps.sort_unstable();
            timestamps.dedup();
        } else {
            timestamps.push(0);
        }
        total_samples += timestamps.len();
        let values = timestamps
            .into_iter()
            .map(|timestamp| {
                let value = sample(identifier, timestamp)?;
                if !value.is_finite() {
                    return Err(BridgeError::InvalidInput("non-finite host animation value"));
                }
                Ok((timestamp, value))
            })
            .collect::<BridgeResult<Vec<_>>>()?;
        rows.push((identifier, values));
    }
    let input_rotation = sample(170, 0)?;
    if !input_rotation.is_finite() {
        return Err(BridgeError::InvalidInput("invalid input rotation"));
    }
    controls::validate(&metadata["controls"])?;
    let encoded = serde_json::to_string(&(2_u32, input_rotation, rows, &metadata["controls"]))?;
    if encoded.len() > MAX_SNAPSHOT_BYTES {
        return Err(BridgeError::InvalidInput(
            "animation snapshot exceeds the memory budget",
        ));
    }
    *cached = Some(Snapshot {
        signature: signature.into(),
        encoded: encoded.clone(),
    });
    Ok(encoded)
}

pub(crate) fn prepare(
    data: &str,
    override_project: bool,
) -> BridgeResult<(KeyframeManager, Value)> {
    if data.len() > MAX_SNAPSHOT_BYTES {
        return Err(BridgeError::InvalidInput(
            "animation snapshot exceeds the memory budget",
        ));
    }
    let mut document: Value = serde_json::from_str(data)?;
    let version = document[0].as_u64().unwrap_or(0);
    let input_rotation = document[1]
        .as_f64()
        .ok_or(BridgeError::InvalidInput("invalid input rotation"))?;
    let values = document.get_mut(3).map(Value::take).unwrap_or(Value::Null);
    let rows: Samples = serde_json::from_value(document[2].take())?;
    if ![1, 2].contains(&version)
        || !input_rotation.is_finite()
        || rows.len() != parameters().count()
    {
        return Err(BridgeError::InvalidInput("unsupported animation snapshot"));
    }
    controls::validate(&values)?;
    let mut curves: BTreeMap<KeyframeType, BTreeMap<i64, Keyframe>> = BTreeMap::new();
    let mut seen = std::collections::BTreeSet::new();
    let mut count = 0_usize;
    for (identifier, samples) in rows {
        let (_, parameter, scale) = parameters()
            .find(|(id, _, _)| *id == identifier)
            .ok_or(BridgeError::InvalidInput("unknown animation parameter"))?;
        count += samples.len();
        if !seen.insert(identifier) || samples.is_empty() || count > MAX_SAMPLES {
            return Err(BridgeError::InvalidInput("invalid animation sample count"));
        }
        let mut previous = None;
        for (timestamp, value) in samples {
            if !value.is_finite() || previous.is_some_and(|previous| timestamp <= previous) {
                return Err(BridgeError::InvalidInput(
                    "animation samples must be finite and ordered",
                ));
            }
            previous = Some(timestamp);
            let enabled = if identifier >= 600 {
                controls::enabled(&values)
                    && (identifier != 612 || values["611"].as_u64() == Some(0))
            } else {
                override_project || identifier < 200
            };
            if enabled {
                curves.entry(parameter).or_default().insert(
                    timestamp,
                    Keyframe {
                        id: 0,
                        value: value / scale,
                        easing: Easing::Smooth,
                    },
                );
            }
        }
    }
    // Same portrait horizon correction as the official plugins.
    let video_rotation = curves
        .get(&KeyframeType::VideoRotation)
        .and_then(|curve| curve.first_key_value().map(|(_, key)| key.value))
        .unwrap_or(0.0);
    if crate::geometry::is_quarter_turn(input_rotation)
        && (video_rotation.rem_euclid(360.0) - input_rotation.rem_euclid(360.0)).abs() < 1.0
        && let Some(curve) = curves.get_mut(&KeyframeType::LockHorizonRoll)
    {
        for key in curve.values_mut() {
            key.value += 180.0;
        }
    }
    // Core's interactive `set` snaps keys within 1 ms together. Importing its native
    // document format preserves off-grid knots and high-frame-rate samples exactly.
    Ok((
        serde_json::from_value(serde_json::json!({
            "keyframes": curves, "gyro_offsets": {}, "timestamp_scale": null,
        }))?,
        values,
    ))
}

#[cfg(test)]
fn provider(data: &str, override_project: bool) -> BridgeResult<KeyframeManager> {
    prepare(data, override_project).map(|(keyframes, _)| keyframes)
}

pub(crate) fn attach(manager: &StabilizationManager, sampled: KeyframeManager, use_project: bool) {
    // Core's render, smoothing and zoom paths all inspect the same native curves.
    // The official plugins use a custom provider for live host data; FxPlug render
    // state is immutable, so materializing it avoids retaining a second curve map.
    bake(manager, &sampled, use_project);
    let keys = manager.keyframes.read();
    let mut parameters = manager.params.write();
    if let Some(rotation) = keys.value_at_video_timestamp(&KeyframeType::VideoRotation, 0.0) {
        parameters.video_rotation = rotation;
    }
    drop(parameters);
    drop(keys);
    manager.invalidate_blocking_smoothing();
}

/// Writes the evaluated curves as ordinary Gyroflow keyframes for portable project exports.
pub(crate) fn bake(manager: &StabilizationManager, sampled: &KeyframeManager, use_project: bool) {
    let mut internal = manager.keyframes.write();
    let mut document = internal.serialize();
    if let (Some(destination), Some(source)) =
        (document.as_object_mut(), sampled.serialize().as_object())
    {
        for (name, curve) in source {
            if !use_project
                || destination
                    .get(name)
                    .and_then(Value::as_object)
                    .is_none_or(|keys| keys.is_empty())
            {
                destination.insert(name.clone(), curve.clone());
            }
        }
    }
    internal.deserialize(&document);
    internal.update_gyro(&manager.gyro.read());
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    const PROJECT: &str =
        include_str!("../../../../Tests/Compatibility/Fixtures/identity.gyroflow");

    fn signature(label: &str, fps: f64) -> Value {
        serde_json::json!({ "test": label, "fps": fps, "input_rotation": 0,
            "parameters": parameters().map(|(id, _, _)| serde_json::json!({
                "id": id, "value": 1.0, "keys": []
            })).collect::<Vec<_>>() })
    }
    pub(crate) fn constant_snapshot(rotation: f64) -> String {
        serde_json::to_string(&(
            1_u32,
            rotation,
            parameters()
                .map(|(id, _, _)| {
                    let value = match id {
                        100 => 1.0,
                        110 => 0.5,
                        120 => 100.0,
                        180 => rotation,
                        210 => 130.0,
                        _ => 0.0,
                    };
                    (id, vec![(0_i64, value)])
                })
                .collect::<Samples>(),
        ))
        .unwrap()
    }

    #[test]
    fn samples_host_curves_at_fractional_frame_rate_and_exact_knots() {
        let fps = 24000.0 / 1001.0;
        let mut metadata = signature("fractional", fps);
        metadata["parameters"][0]["keys"] = serde_json::json!([
            {"time_us": 0}, {"time_us": 500_200}, {"time_us": 1_000_000}
        ]);
        let curve = |time: i64| 1.0 + (time as f64 / 1_000_000.0).powi(2);
        let encoded = snapshot(PROJECT, &metadata.to_string(), |id, time| {
            Ok(if id == 100 { curve(time) } else { 0.0 })
        })
        .unwrap();
        let manager = provider(&encoded, false).unwrap();
        for frame in 0..24 {
            let timestamp = (frame as f64 / fps * 1_000_000.0).round() as i64;
            assert!(
                (manager
                    .value_at_video_timestamp(&KeyframeType::Fov, timestamp as f64 / 1000.0)
                    .unwrap()
                    - curve(timestamp))
                .abs()
                    < 1e-12
            );
        }
        assert!(
            (manager
                .value_at_video_timestamp(&KeyframeType::Fov, 500.2)
                .unwrap()
                - curve(500_200))
            .abs()
                < 1e-12
        );
    }

    #[test]
    fn unchanged_curves_are_cached_but_edits_moves_easing_and_removal_resample() {
        let mut metadata = signature("cache-invalidation", 30.0);
        metadata["parameters"][0]["keys"] = serde_json::json!([
            {"time_us": 0, "shape": "linear"}, {"time_us": 1_000_000, "shape": "linear"}
        ]);
        let mut count = 0;
        let first = snapshot(PROJECT, &metadata.to_string(), |_, _| {
            count += 1;
            Ok(1.0)
        })
        .unwrap();
        assert!(count > parameters().count());
        assert_eq!(
            snapshot(PROJECT, &metadata.to_string(), |_, _| panic!(
                "unchanged curves must not query the host"
            ))
            .unwrap(),
            first
        );
        for (field, value) in [
            ("value", serde_json::json!(2.0)),
            ("time_us", serde_json::json!(800_000)),
            ("shape", serde_json::json!("bezier")),
        ] {
            metadata["parameters"][0]["keys"][1][field] = value;
            let mut resampled = false;
            snapshot(PROJECT, &metadata.to_string(), |_, _| {
                resampled = true;
                Ok(1.0)
            })
            .unwrap();
            assert!(resampled);
        }
        metadata["parameters"][0]["keys"] = serde_json::json!([]);
        let removed = snapshot(PROJECT, &metadata.to_string(), |_, _| Ok(3.0)).unwrap();
        assert_eq!(
            provider(&removed, false)
                .unwrap()
                .value_at_video_timestamp(&KeyframeType::Fov, 900.0),
            Some(3.0)
        );
        metadata["input_rotation"] = 90.into();
        let rotated = snapshot(PROJECT, &metadata.to_string(), |_, _| Ok(90.0)).unwrap();
        assert_ne!(removed, rotated);
    }

    #[test]
    fn internal_keys_win_only_when_requested_and_units_match_legacy_toolbox() {
        let source = constant_snapshot(0.0);
        let manager = StabilizationManager::default();
        manager.keyframes.write().set(&KeyframeType::Fov, 0, 2.0);
        attach(&manager, provider(&source, false).unwrap(), true);
        assert_eq!(
            manager
                .keyframes
                .read()
                .value_at_video_timestamp(&KeyframeType::Fov, 0.0),
            Some(2.0)
        );
        attach(&manager, provider(&source, false).unwrap(), false);
        let keys = manager.keyframes.read();
        for (parameter, expected) in [
            (KeyframeType::Fov, 1.0),
            (KeyframeType::LensCorrectionStrength, 1.0),
            (KeyframeType::SmoothingParamSmoothness, 0.5),
        ] {
            assert_eq!(
                keys.value_at_video_timestamp(&parameter, 0.0),
                Some(expected)
            );
        }
        assert_eq!(
            keys.value_at_video_timestamp(&KeyframeType::MaxZoom, 0.0),
            None
        );
    }

    #[test]
    fn portrait_horizon_correction_matches_official_plugins() {
        for rotation in [90.0, 270.0, -90.0, 89.5] {
            let keys = provider(&constant_snapshot(rotation), true).unwrap();
            assert_eq!(
                keys.value_at_video_timestamp(&KeyframeType::LockHorizonRoll, 0.0),
                Some(180.0)
            );
            assert_eq!(
                keys.value_at_video_timestamp(&KeyframeType::MaxZoom, 0.0),
                Some(130.0)
            );
        }
    }

    #[test]
    fn rejects_corrupt_oversized_and_nonfinite_animation() {
        assert!(provider("null", false).is_err());
        assert!(provider("[99,0,[]]", false).is_err());
        let mut data: Value = serde_json::from_str(&constant_snapshot(0.0)).unwrap();
        data[2][0][1] = serde_json::json!([[10, 1.0], [9, 2.0]]);
        assert!(provider(&data.to_string(), false).is_err());
        let mut metadata = signature("invalid", 0.0);
        assert!(snapshot(PROJECT, &metadata.to_string(), |_, _| Ok(1.0)).is_err());
        metadata["fps"] = 30.into();
        assert!(snapshot(PROJECT, &metadata.to_string(), |_, _| Ok(f64::NAN)).is_err());
        assert!(
            snapshot(PROJECT, &metadata.to_string(), |_, _| Err(
                BridgeError::InvalidInput("host unavailable")
            ))
            .is_err()
        );
        metadata["parameters"][0]["keys"] =
            serde_json::json!([{"time_us": 0}, {"time_us": i64::MAX}]);
        let long_project = PROJECT.replace("1000.0", "1000000000.0");
        assert!(
            snapshot(&long_project, &metadata.to_string(), |_, _| panic!(
                "memory budget checked before sampling"
            ))
            .is_err()
        );
        let excessive_duration = PROJECT.replace("1000.0", "1e300");
        assert!(
            snapshot(&excessive_duration, &metadata.to_string(), |_, _| panic!(
                "extreme durations must be rejected before sampling"
            ))
            .is_err()
        );
    }
}
