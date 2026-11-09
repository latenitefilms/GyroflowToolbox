//! Render configuration and Metal dispatch, serialized per cached stabilization.
use crate::{BridgeError, BridgeResult, cache::Cache, project};
use gyroflow_core::{
    StabilizationManager,
    gpu::{BufferDescription, BufferSource, Buffers},
    keyframes::KeyframeType,
    stabilization::{BGRA8, Interpolation, RGBAf, RGBAf16},
};
use std::ffi::{c_int, c_void};
use std::num::NonZeroUsize;
use std::sync::LazyLock;

/// Versioned C layout for the additional official-plugin controls.
///
/// Default values preserve v1.3.5 behavior. The host stores these fields under new keys.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RenderOptions {
    /// ABI version. Must be 1.
    pub version: u32,
    /// Apply the zoom limit and pitch/yaw below when 1; retain project values when 0.
    pub override_project_settings: u32,
    /// Maximum zoom in percent; zero disables the limit.
    pub zoom_limit: f64,
    /// Additional pitch in degrees.
    pub additional_pitch: f64,
    /// Additional yaw in degrees.
    pub additional_yaw: f64,
    /// -1 retains the project's integration; 0–6 match the official plugin menu.
    pub integration_method: i32,
    /// Lanczos4, RobidouxSharp, Bilinear, Bicubic, Robidoux, Mitchell, CatmullRom (0–6).
    pub interpolation: u32,
    /// Preserve embedded keyframes when 1; use inspector values for exposed controls when 0.
    pub use_project_keyframes: u32,
    /// Reserved for future versions; must be zero.
    pub reserved: u32,
}
impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            version: 1,
            override_project_settings: 0,
            zoom_limit: 130.0,
            additional_pitch: 0.0,
            additional_yaw: 0.0,
            integration_method: -1,
            interpolation: 0,
            use_project_keyframes: 1,
            reserved: 0,
        }
    }
}
impl RenderOptions {
    pub(crate) fn from_project(manager: &StabilizationManager) -> Self {
        let parameters = manager.params.read();
        Self {
            zoom_limit: parameters.max_zoom.unwrap_or(0.0),
            additional_pitch: parameters.additional_rotation.1,
            additional_yaw: parameters.additional_rotation.0,
            ..Self::default()
        }
    }
    fn validate(self) -> BridgeResult<()> {
        if self.version != 1
            || self.reserved != 0
            || self.override_project_settings > 1
            || self.use_project_keyframes > 1
            || !(-1..=6).contains(&self.integration_method)
            || self.interpolation > 6
            || !self.zoom_limit.is_finite()
            || self.zoom_limit < 0.0
            || !self.additional_pitch.is_finite()
            || !self.additional_yaw.is_finite()
        {
            return Err(BridgeError::InvalidInput("invalid render options"));
        }
        Ok(())
    }
    fn interpolation(self) -> Interpolation {
        match self.interpolation {
            1 => Interpolation::RobidouxSharp,
            2 => Interpolation::Bilinear,
            3 => Interpolation::Bicubic,
            4 => Interpolation::Robidoux,
            5 => Interpolation::Mitchell,
            6 => Interpolation::CatmullRom,
            _ => Interpolation::Lanczos4,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PixelFormat {
    Bgra8,
    Rgba16Float,
    Rgba32Float,
}
impl PixelFormat {
    pub(crate) fn parse(name: &str, bytes: c_int) -> BridgeResult<Self> {
        match (name, bytes) {
            ("BGRA8" | "BGRA8Unorm", 1) => Ok(Self::Bgra8),
            ("RGBAf16", 2) => Ok(Self::Rgba16Float),
            ("RGBAf", 4) => Ok(Self::Rgba32Float),
            _ => Err(BridgeError::InvalidInput(
                "unsupported pixel format or component size",
            )),
        }
    }
    fn bytes(self) -> usize {
        match self {
            Self::Bgra8 => 1,
            Self::Rgba16Float => 2,
            Self::Rgba32Float => 4,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Settings {
    pub fov: f64,
    pub smoothness: f64,
    pub lens_correction: f64,
    pub horizon_lock: f64,
    pub horizon_roll: f64,
    pub position_x: f64,
    pub position_y: f64,
    pub input_rotation: f64,
    pub video_rotation: f64,
    pub overview: bool,
}

pub(crate) struct InspectorValues {
    pub settings: Settings,
    pub options: RenderOptions,
    pub disable_stretch: bool,
}
impl InspectorValues {
    pub(crate) fn parse(data: &str) -> BridgeResult<Self> {
        let values: serde_json::Value = serde_json::from_str(data)?;
        crate::parameters::validate(&values)?;
        let number = |identifier: u32| {
            values[identifier.to_string()]
                .as_f64()
                .expect("validated numeric inspector value")
        };
        let flag = |identifier: u32| {
            values[identifier.to_string()]
                .as_bool()
                .expect("validated toggle")
        };
        Ok(Self {
            settings: Settings {
                fov: number(100),
                smoothness: number(110),
                lens_correction: number(120) / 100.0,
                horizon_lock: number(130),
                horizon_roll: number(140),
                position_x: number(150),
                position_y: number(160),
                input_rotation: number(170),
                video_rotation: number(180),
                overview: flag(310),
            },
            options: RenderOptions {
                override_project_settings: u32::from(flag(200)),
                zoom_limit: number(210),
                additional_pitch: number(220),
                additional_yaw: number(230),
                integration_method: number(240) as i32 - 1,
                interpolation: number(250) as u32,
                use_project_keyframes: u32::from(flag(260)),
                ..RenderOptions::default()
            },
            disable_stretch: flag(320),
        })
    }
}
pub(crate) struct Frame<'input> {
    pub host_keyframes: Option<&'input str>,
    pub identifier: &'input str,
    pub path: &'input str,
    pub data: &'input str,
    pub width: u32,
    pub height: u32,
    pub timestamp: i64,
    pub format: PixelFormat,
    pub settings: Settings,
    pub disable_stretch: bool,
    pub input_texture: *mut c_void,
    pub output_texture: *mut c_void,
    pub command_queue: *mut c_void,
    pub options: RenderOptions,
}
impl Frame<'_> {
    pub(crate) fn validate(&self) -> BridgeResult<()> {
        self.options.validate()?;
        let settings = self.settings;
        if self.width == 0
            || self.height == 0
            || self.input_texture.is_null()
            || self.output_texture.is_null()
            || self.input_texture == self.output_texture
            || self.data.is_empty()
            || settings.fov <= 0.0
            || settings.smoothness < 0.0
            || [
                settings.fov,
                settings.smoothness,
                settings.lens_correction,
                settings.horizon_lock,
                settings.horizon_roll,
                settings.position_x,
                settings.position_y,
                settings.input_rotation,
                settings.video_rotation,
            ]
            .iter()
            .any(|value| !value.is_finite())
        {
            return Err(BridgeError::InvalidInput(
                "invalid frame, textures, or stabilization settings",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct CacheKey {
    identifier: String,
    path: String,
    disable_stretch: bool,
    project_keyframes: bool,
    override_project_settings: bool,
}
struct Renderer {
    host_keyframes: Option<String>,
    source: String,
    manager: StabilizationManager,
    project_options: RenderOptions,
    project_integration: usize,
    geometry: Option<(u32, u32, u64)>,
}
static RENDERERS: LazyLock<Cache<CacheKey, Renderer>> =
    LazyLock::new(|| Cache::new(NonZeroUsize::new(8).expect("renderer cache capacity is nonzero")));

pub(crate) fn clear_cache() {
    RENDERERS.clear();
}

impl Renderer {
    fn matches(&self, frame: &Frame<'_>) -> bool {
        // A direct comparison detects edits without rehashing multi-megabyte telemetry every frame.
        self.source == frame.data && self.host_keyframes.as_deref() == frame.host_keyframes
    }

    fn new(frame: &Frame<'_>) -> BridgeResult<Self> {
        let manager = project::import(frame.data)?;
        if frame.disable_stretch {
            manager.disable_lens_stretch(false);
        }
        if frame.host_keyframes.is_none() && frame.options.use_project_keyframes == 0 {
            let mut keyframes = manager.keyframes.write();
            for parameter in [
                KeyframeType::Fov,
                KeyframeType::SmoothingParamSmoothness,
                KeyframeType::LensCorrectionStrength,
                KeyframeType::LockHorizonAmount,
                KeyframeType::LockHorizonRoll,
                KeyframeType::ZoomingCenterX,
                KeyframeType::ZoomingCenterY,
                KeyframeType::VideoRotation,
            ] {
                keyframes.clear_type(&parameter);
            }
            // Advanced project keyframes are only overridden when their inspector controls are enabled.
            if frame.options.override_project_settings != 0 {
                for parameter in [
                    KeyframeType::MaxZoom,
                    KeyframeType::AdditionalRotationX,
                    KeyframeType::AdditionalRotationY,
                ] {
                    keyframes.clear_type(&parameter);
                }
            }
        }
        manager.params.write().framebuffer_inverted = true;
        manager.set_background_color(nalgebra::Vector4::zeros());
        manager.stabilization.write().share_wgpu_instances = true;
        manager.invalidate_blocking_smoothing();
        manager
            .params
            .write()
            .calculate_ramped_timestamps(&manager.keyframes.read(), false, false);
        let project_options = RenderOptions::from_project(&manager);
        let project_integration = manager.gyro.read().integration_method;
        Ok(Self {
            host_keyframes: None,
            source: frame.data.to_owned(),
            manager,
            project_options,
            project_integration,
            geometry: None,
        })
    }

    fn configure(&mut self, frame: &Frame<'_>) -> BridgeResult<()> {
        if let Some(snapshot) = frame.host_keyframes
            && self.host_keyframes.as_deref() != Some(snapshot)
        {
            let (sampled, controls) =
                crate::animation::prepare(snapshot, frame.options.override_project_settings != 0)?;
            crate::controls::apply(&self.manager, &controls)?;
            crate::animation::attach(
                &self.manager,
                sampled,
                frame.options.use_project_keyframes != 0,
            );
            self.host_keyframes = Some(snapshot.to_owned());
        }
        let manager = &self.manager;
        let incoming = frame.settings;
        let advanced = if frame.options.override_project_settings != 0 {
            frame.options
        } else {
            self.project_options
        };
        let mut smoothing_changed = false;
        let mut zoom_changed = false;
        let mut transform_changed = false;
        transform_changed |= replace(&mut manager.params.write().fov_overview, incoming.overview);
        if frame.host_keyframes.is_none() {
            let mut parameters = manager.params.write();
            transform_changed |= replace(&mut parameters.fov, incoming.fov);
            zoom_changed |= replace(
                &mut parameters.lens_correction_amount,
                incoming.lens_correction,
            );
            zoom_changed |= replace(
                &mut parameters.adaptive_zoom_center_offset,
                (incoming.position_x / 100.0, incoming.position_y / 100.0),
            );
            zoom_changed |= replace(&mut parameters.video_rotation, incoming.video_rotation);
            smoothing_changed |= replace(
                &mut parameters.max_zoom,
                if advanced.zoom_limit > 0.0 {
                    Some(advanced.zoom_limit)
                } else {
                    None
                },
            );
            smoothing_changed |= replace(
                &mut parameters.additional_rotation.0,
                advanced.additional_yaw,
            );
            smoothing_changed |= replace(
                &mut parameters.additional_rotation.1,
                advanced.additional_pitch,
            );
        }
        if frame.host_keyframes.is_none() {
            let mut smoothing = manager.smoothing.write();
            if smoothing.current().get_parameter("smoothness") != incoming.smoothness {
                smoothing
                    .current_mut()
                    .set_parameter("smoothness", incoming.smoothness);
                smoothing_changed = true;
            }
            // Preserve the project's pitch, gravity, and automatic-lock options from current Core.
            smoothing_changed |= replace(
                &mut smoothing.horizon_lock.horizonlockpercent,
                incoming.horizon_lock,
            );
            smoothing_changed |= replace(
                &mut smoothing.horizon_lock.horizonroll,
                incoming.horizon_roll,
            );
            smoothing_changed |= replace(
                &mut smoothing.horizon_lock.lock_enabled,
                incoming.horizon_lock > 0.0,
            );
        }
        {
            let integration = if frame.options.integration_method < 0 {
                self.project_integration
            } else {
                frame.options.integration_method as usize
            };
            if manager.gyro.read().integration_method != integration {
                manager.set_integration_method(integration);
                smoothing_changed = true;
            }
        }
        {
            let mut stabilization = manager.stabilization.write();
            let interpolation = frame.options.interpolation();
            if stabilization.interpolation as u32 != interpolation as u32 {
                stabilization.interpolation = interpolation;
                transform_changed = true;
            }
        }
        let reference_rotation = manager.params.read().video_rotation;
        let geometry = (frame.width, frame.height, reference_rotation.to_bits());
        if self.geometry != Some(geometry) {
            let (width, height) = (frame.width as usize, frame.height as usize);
            if frame.host_keyframes.is_some() {
                // The lens calibration and gyro projection use the original video size.
                // Preview resolution belongs to BufferDescription, not StabilizationParams.
                let current = manager.params.read().output_size;
                let aspect = |size: (usize, usize)| size.0 as f64 / size.1.max(1) as f64;
                if current.0 == 0
                    || current.1 == 0
                    || (aspect(current) / aspect((width, height)) - 1.0).abs() > 0.01
                {
                    zoom_changed |= manager.set_output_size(width, height);
                }
            } else {
                // Preserve the original C entry point's sizing for archived render states.
                let (input_width, input_height) =
                    if incoming.video_rotation.rem_euclid(180.0) == 90.0 {
                        (height, width)
                    } else {
                        (width, height)
                    };
                manager.set_size(input_width, input_height);
                manager.set_output_size(width, height);
                zoom_changed = true;
            }
            self.geometry = Some(geometry);
        }
        if smoothing_changed {
            manager.invalidate_blocking_smoothing();
        } else if zoom_changed {
            manager.invalidate_blocking_zooming();
        } else if transform_changed {
            manager.invalidate_blocking_undistortion();
        }
        Ok(())
    }
}

fn replace<Value: PartialEq>(current: &mut Value, incoming: Value) -> bool {
    if *current == incoming {
        false
    } else {
        *current = incoming;
        true
    }
}

pub(crate) fn process(frame: Frame<'_>) -> BridgeResult<()> {
    let key = CacheKey {
        identifier: frame.identifier.into(),
        path: frame.path.into(),
        disable_stretch: frame.disable_stretch,
        project_keyframes: frame.options.use_project_keyframes != 0,
        override_project_settings: frame.options.override_project_settings != 0,
    };
    let slot = RENDERERS.slot(key);
    // One atomic configuration + render transaction per stabilization, never a global render lock.
    let mut cached = slot.lock().expect("renderer mutex poisoned");
    if cached
        .as_ref()
        .is_none_or(|renderer| !renderer.matches(&frame))
    {
        *cached = Some(Renderer::new(&frame)?);
    }
    let renderer = cached.as_mut().expect("renderer initialized above");
    renderer.configure(&frame)?;
    let width = frame.width as usize;
    let height = frame.height as usize;
    let stride = width
        .checked_mul(4 * frame.format.bytes())
        .ok_or(BridgeError::InvalidInput("frame stride overflow"))?;
    let geometry = frame.host_keyframes.map(|_| {
        crate::geometry::for_clip(
            renderer.manager.params.read().size,
            frame.settings.input_rotation,
            (width, height),
        )
    });
    let mut buffers = Buffers {
        input: BufferDescription {
            size: (width, height, stride),
            rect: geometry.map(|geometry| geometry.source_rect),
            data: BufferSource::Metal {
                texture: frame.input_texture,
                command_queue: frame.command_queue,
            },
            rotation: Some(geometry.map_or(frame.settings.input_rotation, |geometry| {
                geometry.input_rotation
            }) as f32),
            texture_copy: false,
        },
        output: BufferDescription {
            size: (width, height, stride),
            rect: None,
            data: BufferSource::Metal {
                texture: frame.output_texture,
                command_queue: frame.command_queue,
            },
            rotation: None,
            texture_copy: false,
        },
    };
    match frame.format {
        PixelFormat::Bgra8 => {
            renderer
                .manager
                .process_pixels::<BGRA8>(frame.timestamp, None, &mut buffers)
        }
        PixelFormat::Rgba16Float => {
            renderer
                .manager
                .process_pixels::<RGBAf16>(frame.timestamp, None, &mut buffers)
        }
        PixelFormat::Rgba32Float => {
            renderer
                .manager
                .process_pixels::<RGBAf>(frame.timestamp, None, &mut buffers)
        }
    }?;
    Ok(())
}

pub(crate) fn export_project(
    data: &str,
    snapshot: &str,
    options: RenderOptions,
) -> BridgeResult<String> {
    options.validate()?;
    let manager = project::import(data)?;
    let (sampled, controls) =
        crate::animation::prepare(snapshot, options.override_project_settings != 0)?;
    crate::controls::apply(&manager, &controls)?;
    crate::animation::bake(&manager, &sampled, options.use_project_keyframes != 0);
    if options.integration_method >= 0 {
        manager.set_integration_method(options.integration_method as usize);
    }
    let mut document: serde_json::Value =
        serde_json::from_str(&project::export_preserving_metadata(&manager, data)?)?;
    document["output"]["interpolation"] = (options.interpolation() as u32).into();
    Ok(serde_json::to_string(&document)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    #[test]
    fn inspector_payload_converts_units_and_validates_in_rust() {
        let mut values = crate::parameters::default_values();
        values["120"] = 85.0.into();
        values["150"] = 25.0.into();
        values["240"] = 3.into();
        values["250"] = 1.into();
        let decoded = InspectorValues::parse(&values.to_string()).unwrap();
        assert_eq!(decoded.settings.lens_correction, 0.85);
        assert_eq!(decoded.settings.position_x, 25.0);
        assert_eq!(decoded.options.integration_method, 2);
        assert_eq!(decoded.options.interpolation, 1);
        assert_eq!(decoded.options.use_project_keyframes, 1);
        values["240"] = 100.into();
        assert!(InspectorValues::parse(&values.to_string()).is_err());
        values.as_object_mut().unwrap().remove("240");
        assert!(InspectorValues::parse(&values.to_string()).is_err());
    }

    fn frame() -> Frame<'static> {
        Frame {
            host_keyframes: None,
            identifier: "test",
            path: "",
            data: "{}",
            width: 64,
            height: 32,
            timestamp: 0,
            format: PixelFormat::Bgra8,
            settings: Settings {
                fov: 1.0,
                smoothness: 0.5,
                lens_correction: 1.0,
                horizon_lock: 0.0,
                horizon_roll: 0.0,
                position_x: 0.0,
                position_y: 0.0,
                input_rotation: 0.0,
                video_rotation: 0.0,
                overview: false,
            },
            disable_stretch: false,
            // These are opaque identities only; configuration tests never submit textures to Metal.
            input_texture: std::ptr::without_provenance_mut(8),
            output_texture: std::ptr::without_provenance_mut(16),
            command_queue: std::ptr::null_mut(),
            options: RenderOptions::default(),
        }
    }

    fn renderer() -> Renderer {
        let manager = StabilizationManager::default();
        {
            let mut parameters = manager.params.write();
            parameters.max_zoom = Some(175.0);
            parameters.additional_rotation = (12.0, -6.0, 3.0);
        }
        let project_options = RenderOptions::from_project(&manager);
        let project_integration = manager.gyro.read().integration_method;
        Renderer {
            host_keyframes: None,
            source: "{}".into(),
            manager,
            project_options,
            project_integration,
            geometry: None,
        }
    }

    #[test]
    fn legacy_frames_preserve_project_zoom_and_orientation() {
        let mut renderer = renderer();
        let mut frame = frame();
        renderer.configure(&frame).unwrap();
        assert_eq!(renderer.manager.params.read().max_zoom, Some(175.0));
        assert_eq!(
            renderer.manager.params.read().additional_rotation,
            (12.0, -6.0, 3.0)
        );
        frame.options.override_project_settings = 1;
        frame.options.additional_yaw = 42.0;
        frame.options.zoom_limit = 150.0;
        renderer.configure(&frame).unwrap();
        assert_eq!(renderer.manager.params.read().max_zoom, Some(150.0));
        assert_eq!(renderer.manager.params.read().additional_rotation.0, 42.0);
        frame.options.override_project_settings = 0;
        renderer.configure(&frame).unwrap();
        assert_eq!(
            renderer.manager.params.read().additional_rotation,
            (12.0, -6.0, 3.0)
        );
    }

    #[test]
    fn project_edits_invalidate_the_same_clip_without_hashing_each_frame() {
        let renderer = renderer();
        let mut frame = frame();
        assert!(renderer.matches(&frame));
        frame.timestamp = 500_000;
        assert!(renderer.matches(&frame));
        frame.data = "{\"version\":3}";
        assert!(!renderer.matches(&frame));
        frame.data = "{}";
        frame.host_keyframes = Some("changed curves");
        assert!(!renderer.matches(&frame));
    }

    #[test]
    fn fov_changes_do_not_recompute_motion_smoothing() {
        let mut renderer = renderer();
        let mut frame = frame();
        renderer.configure(&frame).unwrap();
        renderer
            .manager
            .smoothing_invalidated
            .store(false, Ordering::SeqCst);
        renderer
            .manager
            .zooming_invalidated
            .store(false, Ordering::SeqCst);
        renderer
            .manager
            .undistortion_invalidated
            .store(false, Ordering::SeqCst);
        frame.settings.fov = 1.2;
        renderer.configure(&frame).unwrap();
        assert!(
            !renderer
                .manager
                .smoothing_invalidated
                .load(Ordering::SeqCst)
        );
        assert!(!renderer.manager.zooming_invalidated.load(Ordering::SeqCst));
        assert!(
            renderer
                .manager
                .undistortion_invalidated
                .load(Ordering::SeqCst)
        );
        frame.settings.smoothness = 0.8;
        renderer.configure(&frame).unwrap();
        assert!(
            renderer
                .manager
                .smoothing_invalidated
                .load(Ordering::SeqCst)
        );
    }

    #[test]
    fn first_frame_applies_quarter_turn_geometry() {
        let mut renderer = renderer();
        let mut frame = frame();
        frame.settings.video_rotation = 270.0;
        renderer.configure(&frame).unwrap();
        assert_eq!(renderer.manager.params.read().size, (32, 64));
        assert_eq!(renderer.manager.params.read().output_size, (64, 32));
    }

    #[test]
    fn provider_animation_and_preview_sizes_reuse_whole_clip_smoothing() {
        let mut renderer = renderer();
        renderer.manager.set_size(3840, 2160);
        let snapshot = crate::animation::tests::constant_snapshot(90.0);
        let mut frame = frame();
        frame.host_keyframes = Some(&snapshot);
        frame.width = 1080;
        frame.height = 1920;
        renderer.configure(&frame).unwrap();
        assert_eq!(renderer.manager.params.read().size, (3840, 2160));
        assert_eq!(renderer.manager.params.read().output_size, (2160, 3840));
        renderer
            .manager
            .smoothing_invalidated
            .store(false, Ordering::SeqCst);
        renderer
            .manager
            .zooming_invalidated
            .store(false, Ordering::SeqCst);
        frame.timestamp = 500_000;
        frame.settings.smoothness = 2.0;
        frame.settings.video_rotation = 120.0;
        frame.settings.overview = true;
        frame.width = 270;
        frame.height = 480;
        renderer.configure(&frame).unwrap();
        assert!(
            !renderer
                .manager
                .smoothing_invalidated
                .load(Ordering::SeqCst)
        );
        assert!(!renderer.manager.zooming_invalidated.load(Ordering::SeqCst));
        assert!(renderer.manager.params.read().fov_overview);
        assert_eq!(renderer.manager.params.read().size, (3840, 2160));
    }

    #[test]
    fn exported_animation_uses_native_keys_and_preserves_unexposed_project_curves() {
        let manager = project::import(include_str!(
            "../../../../Tests/Compatibility/Fixtures/identity.gyroflow"
        ))
        .unwrap();
        manager.keyframes.write().set(&KeyframeType::Fov, 0, 1.75);
        manager
            .keyframes
            .write()
            .set(&KeyframeType::VideoSpeed, 0, 0.5);
        let data = project::export(&manager).unwrap();
        let snapshot = crate::animation::tests::constant_snapshot(0.0);
        for (preference, expected) in [(1, 1.75), (0, 1.0)] {
            let exported = export_project(
                &data,
                &snapshot,
                RenderOptions {
                    use_project_keyframes: preference,
                    ..RenderOptions::default()
                },
            )
            .unwrap();
            let reopened = project::import(&exported).unwrap();
            let keys = reopened.keyframes.read();
            assert_eq!(
                keys.value_at_video_timestamp(&KeyframeType::Fov, 500.0),
                Some(expected)
            );
            assert_eq!(
                keys.value_at_video_timestamp(&KeyframeType::VideoSpeed, 500.0),
                Some(0.5)
            );
            assert!(keys.is_keyframed_internally(&KeyframeType::SmoothingParamSmoothness));
        }
    }

    #[test]
    fn advanced_horizon_settings_survive_inspector_updates() {
        let mut renderer = renderer();
        renderer
            .manager
            .smoothing
            .write()
            .horizon_lock
            .automatic_lock = true;
        renderer.manager.smoothing.write().horizon_lock.lock_pitch = true;
        renderer.configure(&frame()).unwrap();
        assert!(
            renderer
                .manager
                .smoothing
                .read()
                .horizon_lock
                .automatic_lock
        );
        assert!(renderer.manager.smoothing.read().horizon_lock.lock_pitch);
    }

    #[test]
    fn rejects_invalid_frames_before_metal_dispatch() {
        let mut frame = frame();
        assert!(frame.validate().is_ok());
        frame.options.version = 99;
        assert!(frame.validate().is_err());
        frame.options = RenderOptions::default();
        frame.settings.fov = f64::NAN;
        assert!(frame.validate().is_err());
        frame.settings.fov = 1.0;
        frame.width = 0;
        assert!(frame.validate().is_err());
        frame.width = 64;
        frame.input_texture = std::ptr::null_mut();
        assert!(frame.validate().is_err());
    }

    #[test]
    fn interpolation_menu_maps_to_official_filters() {
        let expected = [
            Interpolation::Lanczos4,
            Interpolation::RobidouxSharp,
            Interpolation::Bilinear,
            Interpolation::Bicubic,
            Interpolation::Robidoux,
            Interpolation::Mitchell,
            Interpolation::CatmullRom,
        ];
        for (index, expected) in expected.into_iter().enumerate() {
            let options = RenderOptions {
                interpolation: index as u32,
                ..RenderOptions::default()
            };
            assert_eq!(options.interpolation() as u32, expected as u32);
        }
    }
}
