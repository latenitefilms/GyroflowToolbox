use super::*;
use crate::render::PixelFormat;

const PROJECT: &str = r#"{
    "version": 3,
    "video_info": {"width": 64, "height": 32, "fps": 30.0, "num_frames": 30, "duration_ms": 1000.0, "rotation": 90.0},
    "stabilization": {"fov": 1.25, "lens_correction_amount": 0.85,
        "horizon_lock_amount": 35.0, "horizon_lock_roll": -2.5,
        "adaptive_zoom_center_offset": [0.1, -0.05],
        "additional_rotation": [12.0, -6.0, 3.0], "max_zoom": 155.0}
}"#;

/// Takes ownership of a string returned by an FFI entry point.
fn returned_string(pointer: *const c_char) -> String {
    assert!(!pointer.is_null());
    // SAFETY: Tests only pass fresh allocations returned by this library.
    unsafe { CString::from_raw(pointer.cast_mut()) }
        .into_string()
        .unwrap()
}

#[test]
fn accepts_legacy_and_metal_bgra_names() {
    assert_eq!(PixelFormat::parse("BGRA8", 1).unwrap(), PixelFormat::Bgra8);
    assert_eq!(
        PixelFormat::parse("BGRA8Unorm", 1).unwrap(),
        PixelFormat::Bgra8
    );
    assert!(PixelFormat::parse("BGRA8", 4).is_err());
    assert!(PixelFormat::parse("RGBAf16", -2).is_err());
    assert!(PixelFormat::parse("unknown", 1).is_err());
}

#[test]
fn lens_database_is_shared_and_recreated_after_an_explicit_purge() {
    let before = new_manager();
    let shared = new_manager();
    assert!(std::sync::Arc::ptr_eq(
        &before.lens_profile_db,
        &shared.lens_profile_db
    ));
    release_lens_database();
    let after = new_manager();
    assert!(!std::sync::Arc::ptr_eq(
        &before.lens_profile_db,
        &after.lens_profile_db
    ));
    assert_eq!(
        before.lens_profile_db.read().get_all_filenames().len(),
        after.lens_profile_db.read().get_all_filenames().len()
    );
}

#[test]
fn reads_legacy_defaults_in_original_units() {
    let project = CString::new(PROJECT).unwrap();
    let mut values = [0.0_f64; 8];
    let [
        fov,
        smoothness,
        correction,
        horizon,
        roll,
        position_x,
        position_y,
        rotation,
    ] = &mut values;
    // SAFETY: Valid C string and eight distinct aligned outputs.
    let result = unsafe {
        default_values(
            project.as_ptr(),
            fov,
            smoothness,
            correction,
            horizon,
            roll,
            position_x,
            position_y,
            rotation,
        )
    };
    assert_eq!(returned_string(result), "OK");
    assert_eq!(values[0], 1.25);
    assert_eq!(values[2..], [85.0, 35.0, -2.5, 0.1, -0.05, 90.0]);
}

#[test]
fn failed_defaults_do_not_modify_outputs() {
    let mut values = [7.0_f64; 8];
    let [
        fov,
        smoothness,
        correction,
        horizon,
        roll,
        position_x,
        position_y,
        rotation,
    ] = &mut values;
    // SAFETY: Invalid JSON is still a valid C string; outputs are valid allocations.
    let result = unsafe {
        default_values(
            c"invalid".as_ptr(),
            fov,
            smoothness,
            correction,
            horizon,
            roll,
            position_x,
            position_y,
            rotation,
        )
    };
    assert_eq!(returned_string(result), "FAIL");
    assert_eq!(values, [7.0; 8]);
}

#[test]
fn null_strings_and_outputs_fail_without_dereferencing() {
    // SAFETY: Null arguments are explicitly handled by the FFI.
    unsafe {
        assert_eq!(returned_string(lens_identifier(std::ptr::null())), "FAIL");
        assert_eq!(
            returned_string(accurate_timestamps(std::ptr::null())),
            "FAIL"
        );
        assert_eq!(advanced_defaults(c"{}".as_ptr(), std::ptr::null_mut()), 0);
        assert_eq!(render_defaults(std::ptr::null_mut()), 0);
        free_c_string(std::ptr::null_mut());
    }
}

#[test]
fn invalid_utf8_is_rejected() {
    let bytes = [0xff_u8, 0];
    // SAFETY: The input is NUL terminated and valid for the duration of the call.
    assert_eq!(
        returned_string(unsafe { lens_identifier(bytes.as_ptr().cast()) }),
        "FAIL"
    );
}

#[test]
fn invalid_media_and_preset_paths_return_failure() {
    // SAFETY: Static C strings remain valid throughout each call.
    unsafe {
        assert_eq!(
            returned_string(import_media_file(
                c"/nonexistent/gyroflow-test.mp4".as_ptr()
            )),
            "FAIL"
        );
        assert_eq!(
            returned_string(load_preset(
                c"{}".as_ptr(),
                c"/nonexistent/preset.gyroflow".as_ptr()
            )),
            "FAIL"
        );
    }
}

#[test]
fn advanced_defaults_preserve_legacy_behavior() {
    let project = CString::new(PROJECT).unwrap();
    let mut options = RenderOptions::default();
    // SAFETY: C string and output allocation both live throughout the call.
    assert_eq!(
        unsafe { advanced_defaults(project.as_ptr(), &mut options) },
        1
    );
    assert_eq!(options.zoom_limit, 155.0);
    assert_eq!(options.additional_yaw, 12.0);
    assert_eq!(options.additional_pitch, -6.0);
    assert_eq!(options.override_project_settings, 0);
    assert_eq!(options.integration_method, -1);
    assert_eq!(options.use_project_keyframes, 1);
    assert_eq!(options.interpolation, 0);
}

#[test]
fn project_inspection_updates_after_editing_the_same_source() {
    let changed = PROJECT.replace("1.25", "1.75");
    assert_eq!(
        project::inspect(PROJECT, |manager| manager.params.read().fov).unwrap(),
        1.25
    );
    assert_eq!(
        project::inspect(&changed, |manager| manager.params.read().fov).unwrap(),
        1.75
    );
}

#[test]
fn preset_files_are_read_and_foreign_telemetry_is_excluded() {
    let path = std::env::temp_dir().join(format!(
        "gyroflow-preset-test-{}.gyroflow",
        std::process::id()
    ));
    let input = r#"{"version":3,"videofile":"other.mov","video_info":{"fps":120},
        "gyro_source":{"raw_imu":[1,2,3],"filepath":"other.mov","integration_method":2},
        "offsets":{"0":500},"trim_ranges":[[0.1,0.2]],
        "stabilization":{"fov":1.8},"output":{"output_width":3840,"output_path":"foreign.mov"}}"#;
    std::fs::write(&path, input).unwrap();
    let preset = project::read_preset(path.to_str().unwrap()).unwrap();
    std::fs::remove_file(path).unwrap();
    let value: serde_json::Value = serde_json::from_str(&preset).unwrap();
    assert_eq!(value["stabilization"]["fov"], 1.8);
    assert_eq!(value["gyro_source"]["integration_method"], 2);
    for key in ["videofile", "video_info", "offsets", "trim_ranges"] {
        assert!(value.get(key).is_none(), "{key}");
    }
    assert!(value["gyro_source"].get("raw_imu").is_none());
    assert!(value["output"].get("output_path").is_none());
}

#[test]
fn ffi_catches_panics_and_returns_owned_failure_strings() {
    assert_eq!(
        returned_string(ffi_string(|| panic!("simulated engine panic"))),
        "FAIL"
    );
    assert_eq!(ffi_status(|| panic!("simulated engine panic")), 0);
}

#[test]
fn render_options_match_the_c_layout() {
    assert_eq!(std::mem::size_of::<RenderOptions>(), 48);
    assert_eq!(std::mem::align_of::<RenderOptions>(), 8);
    assert_eq!(std::mem::offset_of!(RenderOptions, integration_method), 32);
    assert_eq!(
        std::mem::offset_of!(RenderOptions, use_project_keyframes),
        40
    );
}

#[test]
fn inspector_definitions_have_unique_identifiers() {
    let definitions = returned_string(parameter_definitions());
    let definitions: Vec<serde_json::Value> = serde_json::from_str(&definitions).unwrap();
    let identifiers: std::collections::BTreeSet<_> = definitions
        .iter()
        .filter_map(|value| value["id"].as_u64())
        .collect();
    assert_eq!(
        identifiers.len(),
        definitions
            .iter()
            .filter(|value| value.get("id").is_some())
            .count()
    );
    assert!(
        identifiers
            .iter()
            .all(|identifier| (1..700).contains(identifier))
    );
}

#[test]
fn accurate_red_timing_survives_embedded_project_round_trip() {
    let parser = gyroflow_core::telemetry_parser::SupportedFormats::RedR3d(Default::default());
    let accurate = match parser {
        gyroflow_core::telemetry_parser::SupportedFormats::RedR3d(parser) => {
            parser.has_accurate_timestamps()
        }
        _ => unreachable!("constructed a RED parser"),
    };
    assert!(accurate);
    let manager = project::import(PROJECT).unwrap();
    let metadata = gyroflow_core::gyro_source::FileMetadata {
        has_accurate_timestamps: accurate,
        detected_source: Some("RED RAW".into()),
        quaternions: [
            (0, nalgebra::UnitQuaternion::identity()),
            (1_000_000, nalgebra::UnitQuaternion::identity()),
        ]
        .into(),
        ..Default::default()
    };
    manager.gyro.write().load_from_telemetry(metadata);
    let data = CString::new(project::export(&manager).unwrap()).unwrap();
    // SAFETY: The exported CString lives until both FFI calls return.
    unsafe {
        assert_eq!(returned_string(accurate_timestamps(data.as_ptr())), "YES");
        assert_eq!(
            returned_string(contains_stabilization_data(data.as_ptr())),
            "YES"
        );
        assert_eq!(
            returned_string(accurate_timestamps(c"not JSON".as_ptr())),
            "FAIL"
        );
    }
}
