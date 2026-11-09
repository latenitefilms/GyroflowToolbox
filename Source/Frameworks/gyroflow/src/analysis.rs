//! Cancellable, bounded analysis sessions fed by FxPlug's native frame-analysis callbacks.

use crate::{BridgeError, BridgeResult, parameters, project};
use gyroflow_core::StabilizationManager;
use gyroflow_core::synchronization::{
    AutosyncError, AutosyncProcess, AutosyncResult, SyncParams,
    optical_motion::OpticalMotionAnalysis,
};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::sync::{
    Arc, LazyLock, Mutex,
    atomic::{AtomicBool, AtomicU64, Ordering},
};

const MAX_SESSIONS: usize = 4;
const MAX_FRAME_PIXELS: usize = 4096 * 4096;
static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);
static SESSIONS: LazyLock<Mutex<BTreeMap<u64, Arc<Session>>>> =
    LazyLock::new(|| Mutex::new(BTreeMap::new()));

pub(crate) fn definitions() -> Vec<parameters::Parameter> {
    use parameters::{button, end_group, group, menu, slider, toggle};
    vec![
        group(700, "Motion Analysis", true),
        menu(701, "Tracking", 0, &["KLT", "GMFlow (AI)"]).symbol("kCB_AnalysisTracking"),
        toggle(702, "Ignore Recorded Motion", false).symbol("kCB_IgnoreRecordedMotion"),
        slider(703, "Optical Correction Strength", 50.0, 0.0, 100.0, 1.0)
            .animated(false)
            .symbol("kCB_OpticalStrength"),
        toggle(704, "Correct Each Frame", false).symbol("kCB_OpticalPerFrame"),
        slider(705, "Sync Search Range (s)", 5.0, 0.1, 30.0, 0.1)
            .animated(false)
            .symbol("kCB_SyncSearchRange"),
        slider(706, "Initial Sync Offset (s)", 0.0, -30.0, 30.0, 0.01)
            .animated(false)
            .symbol("kCB_InitialSyncOffset"),
        button(707, "Analyse Motion").symbol("kCB_AnalyseMotion"),
        button(708, "Synchronise Motion Data").symbol("kCB_AutoSync"),
        button(709, "Analyse Lens Metadata Delay").symbol("kCB_AnalyseLensDelay"),
        button(710, "Clear Optical Analysis").symbol("kCB_ClearOpticalAnalysis"),
        button(711, "Cancel Analysis").symbol("kCB_CancelAnalysis"),
        end_group(),
    ]
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Optical,
    Synchronize,
    LensDelay,
}

enum Process {
    Optical(Box<OpticalMotionAnalysis>),
    Synchronize(Box<AutosyncProcess>),
}

struct Job {
    original_source: String,
    original_trim_ranges: Vec<(f64, f64)>,
    input_rotation: f64,
    source_size: (usize, usize),
    manager: StabilizationManager,
    process: Option<Process>,
    result: Arc<Mutex<Option<AutosyncResult>>>,
    mode: Mode,
    ranges: Vec<(f64, f64)>,
    frames: usize,
    last_timestamp: Option<i64>,
}

impl Job {
    fn wants_frame(&self, timestamp_us: i64) -> bool {
        let milliseconds = timestamp_us as f64 / 1000.0;
        self.ranges
            .iter()
            .any(|(start, end)| milliseconds >= *start - 0.5 && milliseconds <= *end + 0.5)
    }
}

pub(crate) fn wants_frame(identifier: u64, timestamp_us: i64) -> BridgeResult<bool> {
    let session = session(identifier)?;
    if session.cancel.load(Ordering::Acquire) {
        return Err(BridgeError::InvalidInput("analysis cancelled"));
    }
    Ok(session
        .job
        .lock()
        .expect("analysis session mutex poisoned")
        .wants_frame(timestamp_us))
}

struct Session {
    cancel: Arc<AtomicBool>,
    job: Mutex<Job>,
}

fn session(identifier: u64) -> BridgeResult<Arc<Session>> {
    SESSIONS
        .lock()
        .expect("analysis registry mutex poisoned")
        .get(&identifier)
        .cloned()
        .ok_or(BridgeError::InvalidInput("analysis session has ended"))
}

fn finite_number(
    request: &Value,
    key: &str,
    default: f64,
    range: std::ops::RangeInclusive<f64>,
) -> BridgeResult<f64> {
    let value = request
        .get(key)
        .map_or(Some(default), Value::as_f64)
        .filter(|value| value.is_finite() && range.contains(value))
        .ok_or(BridgeError::InvalidInput("invalid analysis setting"))?;
    Ok(value)
}

/// Converts inspector values into Core analysis settings in one place.
pub(crate) fn begin_with_parameters(
    source: &str,
    original_source: &str,
    values: &str,
    request: &Value,
) -> BridgeResult<Value> {
    let values: Value = serde_json::from_str(values)?;
    parameters::validate(&values)?;
    if !request.is_object() {
        return Err(BridgeError::InvalidInput("invalid analysis request"));
    }
    let mut configuration = request.clone();
    configuration["tracking"] = if values["701"].as_i64() == Some(1) {
        "gmflow"
    } else {
        "klt"
    }
    .into();
    configuration["ignore_motion"] = values["702"].clone();
    configuration["strength"] = (values["703"].as_f64().unwrap_or(50.0) / 100.0).into();
    configuration["per_frame"] = values["704"].clone();
    configuration["search_range"] = values["705"].clone();
    configuration["initial_offset"] = values["706"].clone();
    let original: Value = serde_json::from_str(original_source)?;
    if !original.is_object() {
        return Err(BridgeError::InvalidInput("invalid original project"));
    }
    let result = begin(source, &configuration)?;
    let identifier = result["session"]
        .as_u64()
        .expect("analysis returns a session ID");
    let session = session(identifier)?;
    let mut job = session.job.lock().expect("analysis session mutex poisoned");
    job.original_source = original_source.to_owned();
    // Match rendering when the user corrects the host's orientation in the Inspector.
    job.input_rotation = values["170"].as_f64().expect("validated input rotation");
    Ok(result)
}

/// Inspector seconds are converted once to Core's millisecond-based synchronization API.
fn sync_configuration(
    request: &Value,
    tracking: &str,
    duration_ms: f64,
) -> BridgeResult<SyncParams> {
    Ok(SyncParams {
        initial_offset: finite_number(request, "initial_offset", 0.0, -30.0..=30.0)? * 1000.0,
        search_size: finite_number(request, "search_range", 5.0, 0.1..=30.0)? * 1000.0,
        time_per_syncpoint: duration_ms.min(3000.0),
        max_sync_points: 3,
        every_nth_frame: 1,
        // GMFlow feeds rs-sync. Core's newer optical-offset solver itself uses KLT.
        of_method: if tracking == "gmflow" { 3 } else { 1 },
        offset_method: if tracking == "gmflow" { 2 } else { 3 },
        ..SyncParams::default()
    })
}

pub(crate) fn begin(source: &str, request: &Value) -> BridgeResult<Value> {
    let mode = match request["mode"].as_str() {
        Some("optical") => Mode::Optical,
        Some("synchronize") => Mode::Synchronize,
        Some("lens_delay") => Mode::LensDelay,
        _ => return Err(BridgeError::InvalidInput("unknown analysis mode")),
    };
    let tracking = match request["tracking"].as_str() {
        None | Some("klt") => "klt",
        Some("gmflow") => "gmflow",
        _ => return Err(BridgeError::InvalidInput("unknown tracking method")),
    };
    if SESSIONS
        .lock()
        .expect("analysis registry mutex poisoned")
        .len()
        >= MAX_SESSIONS
    {
        return Err(BridgeError::InvalidInput(
            "four clips are already being analysed; wait for one to finish",
        ));
    }
    let manager = project::import(source)?;
    let original_trim_ranges = manager.params.read().trim_ranges.clone();
    let input_rotation = project::input_rotation(source, &manager).unwrap_or(0.0);
    let source_size = manager.params.read().size;
    let duration = manager.params.read().duration_ms;
    if !duration.is_finite() || duration <= 0.0 || source_size.0 < 8 || source_size.1 < 8 {
        return Err(BridgeError::InvalidInput(
            "load media before analysing motion",
        ));
    }
    if manager.lens.read().calib_dimension.w == 0 {
        return Err(BridgeError::InvalidInput(
            "load a lens profile or set a focal length before analysis",
        ));
    }
    let start_ms = finite_number(request, "start_ms", 0.0, 0.0..=duration)?;
    // Hosts can round the last frame boundary up while the media metadata rounds duration down.
    let frame_ms = 1000.0 / manager.params.read().fps.max(1.0);
    let end_ms =
        finite_number(request, "end_ms", duration, 0.0..=duration + frame_ms)?.min(duration);
    if end_ms <= start_ms {
        return Err(BridgeError::InvalidInput("the analysis range is empty"));
    }
    {
        let mut parameters = manager.params.write();
        parameters.trim_ranges = vec![(start_ms / duration, end_ms / duration)];
        // GPU zero selects Core's first available Metal device. CPU is never requested.
        parameters.current_device = 0;
    }
    if mode == Mode::Synchronize && !manager.gyro.read().file_metadata.read().has_motion() {
        return Err(BridgeError::InvalidInput(
            "this clip has no recorded motion; use Analyse Motion to measure motion from its images",
        ));
    }
    if tracking == "gmflow" {
        if crate::resources::configured().is_none() {
            return Err(BridgeError::InvalidInput(
                "the bundled GMFlow model is unavailable",
            ));
        }
        gyroflow_core::synchronization::GmflowDenseFlow::prepare()
            .map_err(BridgeError::Operation)?;
    }
    let cancel = Arc::new(AtomicBool::new(false));
    let result = Arc::new(Mutex::new(None));
    let process = match mode {
        Mode::Optical => {
            manager.set_ignore_file_motion(request["ignore_motion"].as_bool().unwrap_or(false));
            manager.set_optical_tracking(tracking);
            manager.set_optical_correction_strength(finite_number(
                request,
                "strength",
                0.5,
                0.0..=1.0,
            )?);
            manager
                .set_optical_correction_per_frame(request["per_frame"].as_bool().unwrap_or(false));
            Process::Optical(Box::new(
                OpticalMotionAnalysis::from_manager(&manager, cancel.clone())
                    .map_err(BridgeError::Operation)?,
            ))
        }
        Mode::Synchronize | Mode::LensDelay => {
            let configuration = sync_configuration(request, tracking, end_ms - start_ms)?;
            let length = end_ms - start_ms;
            let positions: Vec<f64> = [0.2, 0.5, 0.8]
                .iter()
                .map(|fraction| (start_ms + length * fraction) / duration)
                .collect();
            let name = if mode == Mode::LensDelay {
                "estimate_lens_delay"
            } else {
                "synchronize"
            };
            let mut process = AutosyncProcess::from_manager(
                &manager,
                &positions,
                configuration,
                name.to_owned(),
                cancel.clone(),
            )
            .map_err(|error| BridgeError::InvalidInput(match error {
                AutosyncError::NoZoomInMetadata => "the imported media has no changing focal-length metadata; choose a clip that includes a zoom",
                AutosyncError::InvalidParameters => "the clip is too short for these synchronisation settings",
            }))?;
            let output = result.clone();
            process.on_finished(move |value| {
                *output.lock().expect("analysis result mutex poisoned") = Some(value);
            });
            Process::Synchronize(Box::new(process))
        }
    };
    let ranges = match &process {
        Process::Optical(process) => process.ranges_ms(),
        Process::Synchronize(process) => process.get_ranges(),
    };
    let identifier = NEXT_SESSION.fetch_add(1, Ordering::Relaxed);
    let mut sessions = SESSIONS.lock().expect("analysis registry mutex poisoned");
    if sessions.len() >= MAX_SESSIONS {
        return Err(BridgeError::InvalidInput(
            "four clips are already being analysed; wait for one to finish",
        ));
    }
    sessions.insert(
        identifier,
        Arc::new(Session {
            cancel,
            job: Mutex::new(Job {
                original_source: source.to_owned(),
                original_trim_ranges,
                input_rotation,
                source_size,
                manager,
                process: Some(process),
                result,
                mode,
                ranges: ranges.clone(),
                frames: 0,
                last_timestamp: None,
            }),
        }),
    );
    Ok(json!({"session": identifier, "ranges": ranges}))
}

pub(crate) struct GrayFrame<'pixels> {
    pub timestamp_us: i64,
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub pixels: &'pixels [u8],
}

impl GrayFrame<'_> {
    fn validate(&self) -> BridgeResult<()> {
        let size =
            self.stride
                .checked_mul(self.height as usize)
                .ok_or(BridgeError::InvalidInput(
                    "analysis frame dimensions overflow",
                ))?;
        if self.timestamp_us < 0
            || self.width < 8
            || self.height < 8
            || self.stride < self.width as usize
            || size > MAX_FRAME_PIXELS
            || self.pixels.len() < size
        {
            return Err(BridgeError::InvalidInput("invalid analysis frame"));
        }
        Ok(())
    }
}

pub(crate) fn feed(identifier: u64, frame: GrayFrame<'_>) -> BridgeResult<()> {
    frame.validate()?;
    let session = session(identifier)?;
    if session.cancel.load(Ordering::Acquire) {
        return Err(BridgeError::InvalidInput("analysis cancelled"));
    }
    let mut job = session.job.lock().expect("analysis session mutex poisoned");
    if job
        .last_timestamp
        .is_some_and(|last| frame.timestamp_us < last)
    {
        return Err(BridgeError::InvalidInput(
            "analysis frames must arrive in source-time order",
        ));
    }
    if job.last_timestamp == Some(frame.timestamp_us) {
        return Ok(());
    }
    job.last_timestamp = Some(frame.timestamp_us);
    if !job.wants_frame(frame.timestamp_us) {
        return Ok(());
    }
    let frame_number = job.frames;
    match job
        .process
        .as_mut()
        .ok_or(BridgeError::InvalidInput("analysis already finished"))?
    {
        Process::Optical(process) => process
            .feed_frame(
                frame.timestamp_us,
                frame.width,
                frame.height,
                frame.stride,
                frame.pixels,
            )
            .map_err(BridgeError::Operation)?,
        Process::Synchronize(process) => process.feed_frame(
            frame.timestamp_us,
            frame_number,
            frame.width,
            frame.height,
            frame.stride,
            frame.pixels,
        ),
    }
    job.frames += 1;
    Ok(())
}

pub(crate) fn cancel(identifier: u64) {
    if let Ok(session) = session(identifier) {
        session.cancel.store(true, Ordering::Release);
    }
}

/// Shares render geometry with the native GPU converter, including portrait and letterboxed clips.
pub(crate) fn frame_layout(identifier: u64, width: u32, height: u32) -> BridgeResult<Value> {
    if width < 8 || height < 8 || width > 32768 || height > 32768 {
        return Err(BridgeError::InvalidInput(
            "invalid analysis texture dimensions",
        ));
    }
    let session = session(identifier)?;
    let job = session.job.lock().expect("analysis session mutex poisoned");
    let size = job.source_size;
    let rotation = job.input_rotation;
    let layout = crate::geometry::for_clip(size, rotation, (width as usize, height as usize));
    let scale = (960.0 / size.0.max(size.1) as f64).min(1.0);
    Ok(
        json!({"crop": layout.source_rect, "rotation": layout.input_rotation,
        "width": (size.0 as f64 * scale).round().max(8.0) as u32,
        "height": (size.1 as f64 * scale).round().max(8.0) as u32}),
    )
}

pub(crate) fn release(identifier: u64) {
    let session = SESSIONS
        .lock()
        .expect("analysis registry mutex poisoned")
        .remove(&identifier);
    if let Some(session) = session {
        session.cancel.store(true, Ordering::Release);
    }
}

pub(crate) fn finish(identifier: u64) -> BridgeResult<Value> {
    let session = session(identifier)?;
    let mut job = session.job.lock().expect("analysis session mutex poisoned");
    if session.cancel.load(Ordering::Acquire) {
        return Err(BridgeError::InvalidInput("analysis cancelled"));
    }
    if job.frames < 2 {
        return Err(BridgeError::InvalidInput(
            "not enough frames were supplied for analysis",
        ));
    }
    let process = job
        .process
        .take()
        .ok_or(BridgeError::InvalidInput("analysis already finished"))?;
    let mut summary = json!({"frames": job.frames});
    match process {
        Process::Optical(process) => {
            let measurements = process.finish().map_err(BridgeError::Operation)?;
            job.manager
                .set_optical_measurements(measurements)
                .map_err(BridgeError::Operation)?;
            summary["optical"] = job.manager.optical_correction_info();
        }
        Process::Synchronize(process) => {
            process.finished_feeding_frames();
            let result = job
                .result
                .lock()
                .expect("analysis result mutex poisoned")
                .take();
            match result {
                Some(AutosyncResult::Offsets(offsets)) if !offsets.is_empty() => {
                    let mut gyro = job.manager.gyro.write();
                    gyro.prevent_recompute = true;
                    for (timestamp, offset, _) in &offsets {
                        if !timestamp.is_finite() || !offset.is_finite() {
                            return Err(BridgeError::InvalidInput(
                                "synchronisation returned invalid timing",
                            ));
                        }
                        let gyro_timestamp = ((timestamp - offset) * 1000.0).round() as i64;
                        gyro.remove_offsets_near(gyro_timestamp, 100.0);
                        gyro.set_offset(gyro_timestamp, *offset);
                    }
                    gyro.prevent_recompute = false;
                    gyro.adjust_offsets();
                    job.manager.keyframes.write().update_gyro(&gyro);
                    summary["sync_points"] = offsets.len().into();
                }
                Some(AutosyncResult::LensDelay(Some(estimate))) => {
                    job.manager.params.write().lens_metadata_delay_frames = estimate.delay_frames;
                    summary["lens_delay_frames"] = estimate.delay_frames.into();
                    summary["correlation"] = estimate.correlation.into();
                }
                _ => {
                    return Err(BridgeError::InvalidInput(
                        "no reliable result was found; choose a section with clear camera movement or zoom",
                    ));
                }
            }
        }
    }
    if session.cancel.load(Ordering::Acquire) {
        return Err(BridgeError::InvalidInput("analysis cancelled"));
    }
    job.manager.recompute_gyro();
    // Analysis ranges select what is measured, not a new trim of the user's source project.
    job.manager
        .params
        .write()
        .trim_ranges
        .clone_from(&job.original_trim_ranges);
    let analysed: Value = serde_json::from_str(&project::export(&job.manager)?)?;
    let (document, controls) = merge_result(&job.original_source, job.mode, &analysed)?;
    summary["project"] = serde_json::to_string(&document)?.into();
    summary["controls"] = controls;
    summary["mode"] = match job.mode {
        Mode::Optical => "optical",
        Mode::Synchronize => "synchronize",
        Mode::LensDelay => "lens_delay",
    }
    .into();
    Ok(summary)
}

/// Analysis commits telemetry, timing or lens delay, leaving existing inspector animation intact.
fn merge_result(original: &str, mode: Mode, analysed: &Value) -> BridgeResult<(Value, Value)> {
    let mut document: Value = serde_json::from_str(original)?;
    let controls = match mode {
        Mode::Optical => {
            document["gyro_source"] = analysed["gyro_source"].clone();
            document["offsets"] = analysed["offsets"].clone();
            json!({"640": 0.0, "643": true})
        }
        Mode::Synchronize => {
            document["offsets"] = analysed["offsets"].clone();
            json!({"640": 0.0})
        }
        Mode::LensDelay => {
            let delay = analysed["stabilization"]["lens_metadata_delay_frames"].clone();
            document["stabilization"]["lens_metadata_delay_frames"] = delay.clone();
            json!({"633": delay})
        }
    };
    Ok((document, controls))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_validation_bounds_memory_and_checks_rows() {
        let valid = GrayFrame {
            timestamp_us: 12_345,
            width: 8,
            height: 8,
            stride: 8,
            pixels: &[0; 64],
        };
        assert!(valid.validate().is_ok());
        assert!(
            GrayFrame {
                stride: usize::MAX,
                ..valid
            }
            .validate()
            .is_err()
        );
        assert!(
            GrayFrame {
                pixels: &[0; 63],
                ..valid
            }
            .validate()
            .is_err()
        );
        assert!(
            GrayFrame {
                timestamp_us: -1,
                ..valid
            }
            .validate()
            .is_err()
        );
    }

    #[test]
    fn analysis_settings_reject_non_numeric_and_out_of_range_values() {
        assert!(finite_number(&json!({"strength": "NaN"}), "strength", 0.5, 0.0..=1.0).is_err());
        assert!(finite_number(&json!({"strength": 2}), "strength", 0.5, 0.0..=1.0).is_err());
    }
    #[test]
    fn sync_seconds_become_core_milliseconds_and_only_gpu_trackers_are_selected() {
        let settings = sync_configuration(
            &json!({"initial_offset": -1.25, "search_range": 5.0}),
            "klt",
            9000.0,
        )
        .unwrap();
        assert_eq!(settings.initial_offset, -1250.0);
        assert_eq!(settings.search_size, 5000.0);
        assert_eq!(settings.time_per_syncpoint, 3000.0);
        assert_eq!(settings.of_method, 1);
        assert_eq!(settings.offset_method, 3);
        let ai = sync_configuration(&json!({}), "gmflow", 800.0).unwrap();
        assert_eq!(ai.of_method, 3);
        assert_eq!(ai.offset_method, 2);
        assert_eq!(ai.time_per_syncpoint, 800.0);
    }

    #[test]
    fn invalid_projects_and_unknown_sessions_fail_without_touching_the_gpu() {
        assert!(begin("{}", &json!({"mode": "optical"})).is_err());
        assert!(begin("{}", &json!({"mode": "unknown"})).is_err());
        assert!(
            begin_with_parameters(
                "{}",
                "{}",
                &parameters::default_values().to_string(),
                &Value::Null
            )
            .is_err()
        );
        assert!(finish(u64::MAX).is_err());
        cancel(u64::MAX);
        release(u64::MAX);
    }
    #[test]
    fn analysis_never_bakes_host_controls_into_the_saved_project() {
        let original = json!({"stabilization": {"fov": 1.2}, "keyframes": {"Fov": {"0": {"value": 1.1}}}, "offsets": {"0": 5.0}});
        let analysed = json!({"stabilization": {"fov": 2.5, "lens_metadata_delay_frames": 3},
            "keyframes": {"Fov": {"0": {"value": 2.5}}}, "offsets": {"0": 12.0}, "gyro_source": {"optical_correction": "result"}});
        for mode in [Mode::Optical, Mode::Synchronize, Mode::LensDelay] {
            let (saved, controls) = merge_result(&original.to_string(), mode, &analysed).unwrap();
            assert_eq!(saved["keyframes"], original["keyframes"]);
            assert_eq!(saved["stabilization"]["fov"], 1.2);
            if mode == Mode::LensDelay {
                assert_eq!(controls["633"], 3);
                assert_eq!(saved["offsets"], original["offsets"]);
            } else {
                assert_eq!(controls["640"], 0.0);
                assert_eq!(saved["offsets"], analysed["offsets"]);
            }
        }
    }
}
