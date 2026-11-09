//! Owned JSON results and borrowed frame buffers for native analysis and preset actions.

use crate::{BridgeError, analysis, boundary, ffi_json, input_string, presets};
use serde_json::json;
use std::ffi::c_char;

/// Configures sandbox storage and the bundled, pinned GMFlow model before Core is used.
/// Returns owned JSON; release with `freeCString`.
///
/// # Safety
/// Both arguments must be readable NUL-terminated UTF-8 paths until return.
#[unsafe(export_name = "configureToolboxResources")]
pub unsafe extern "C" fn configure_resources(
    data_directory: *const c_char,
    model: *const c_char,
) -> *const c_char {
    ffi_json(|| {
        // SAFETY: Both strings remain owned by the synchronous caller.
        let paths = unsafe {
            crate::resources::RuntimePaths {
                data_directory: input_string(data_directory)?.into(),
                gmflow_model: input_string(model)?.into(),
            }
        };
        crate::resources::configure(paths)?;
        Ok(json!({}))
    })
}

/// Executes a preset or lens action. Returns owned JSON; release with `freeCString`.
///
/// # Safety
/// Every argument must be a readable NUL-terminated UTF-8 string until return.
#[unsafe(export_name = "toolboxCommand")]
pub unsafe extern "C" fn command(
    source: *const c_char,
    snapshot: *const c_char,
    values: *const c_char,
    request: *const c_char,
) -> *const c_char {
    ffi_json(|| {
        // SAFETY: The native caller retains the project, animation and request strings.
        unsafe {
            presets::command(
                input_string(source)?,
                input_string(snapshot)?,
                input_string(values)?,
                &serde_json::from_str(input_string(request)?)?,
            )
        }
    })
}

/// Begins one bounded GPU analysis session and returns its ID and source-time ranges.
/// Returns owned JSON; release with `freeCString`. The caller must release every successful session.
///
/// # Safety
/// Arguments must be readable NUL-terminated UTF-8 JSON strings until return.
#[unsafe(export_name = "beginToolboxAnalysis")]
pub unsafe extern "C" fn begin(
    source: *const c_char,
    original_source: *const c_char,
    values: *const c_char,
    request: *const c_char,
) -> *const c_char {
    ffi_json(|| {
        // SAFETY: Native strings are borrowed only for this call.
        unsafe {
            analysis::begin_with_parameters(
                input_string(source)?,
                input_string(original_source)?,
                input_string(values)?,
                &serde_json::from_str(input_string(request)?)?,
            )
        }
    })
}

/// Returns 1 when a frame is needed, 0 outside the requested sync windows, or -1 after cancellation.
/// Hosts can skip GPU conversion for unused frames without allocating a JSON response.
#[unsafe(export_name = "toolboxWantsAnalysisFrame")]
pub extern "C" fn wants_frame(identifier: u64, timestamp_us: i64) -> i32 {
    match boundary(|| analysis::wants_frame(identifier, timestamp_us)) {
        Ok(needed) => i32::from(needed),
        Err(_) => -1,
    }
}

/// Feeds a top-down, full-image GRAY8 frame at its source presentation timestamp.
/// Pixels are consumed/copied before return. Returns owned JSON; release with `freeCString`.
///
/// # Safety
/// `pixels` must reference at least `length` readable bytes until return, with no concurrent writer.
#[unsafe(export_name = "feedToolboxAnalysis")]
pub unsafe extern "C" fn feed(
    identifier: u64,
    timestamp_us: i64,
    width: u32,
    height: u32,
    stride: usize,
    pixels: *const u8,
    length: usize,
) -> *const c_char {
    ffi_json(|| {
        if pixels.is_null() || length > 4096 * 4096 {
            return Err(BridgeError::InvalidInput("invalid analysis buffer"));
        }
        // SAFETY: Length is bounded above; allocation validity is the native caller's contract.
        let pixels = unsafe { std::slice::from_raw_parts(pixels, length) };
        analysis::feed(
            identifier,
            analysis::GrayFrame {
                timestamp_us,
                width,
                height,
                stride,
                pixels,
            },
        )?;
        Ok(json!({}))
    })
}

/// Finishes a complete analysis, returning an owned project or an error without mutating host state.
/// Release the JSON using `freeCString` and the session using `releaseToolboxAnalysis`.
#[unsafe(export_name = "finishToolboxAnalysis")]
pub extern "C" fn finish(identifier: u64) -> *const c_char {
    ffi_json(|| analysis::finish(identifier))
}

/// Returns a bounded crop, rotation and GRAY8 size for the native Metal image converter.
/// Release the returned JSON using `freeCString`.
#[unsafe(export_name = "toolboxAnalysisFrameLayout")]
pub extern "C" fn frame_layout(identifier: u64, width: u32, height: u32) -> *const c_char {
    ffi_json(|| analysis::frame_layout(identifier, width, height))
}

/// Requests cancellation without waiting for an in-flight GPU frame.
#[unsafe(export_name = "cancelToolboxAnalysis")]
pub extern "C" fn cancel(identifier: u64) {
    let _ = boundary(|| {
        analysis::cancel(identifier);
        Ok(())
    });
}

/// Cancels and removes a session; safe to repeat or call for an unknown ID.
#[unsafe(export_name = "releaseToolboxAnalysis")]
pub extern "C" fn release(identifier: u64) {
    let _ = boundary(|| {
        analysis::release(identifier);
        Ok(())
    });
}
