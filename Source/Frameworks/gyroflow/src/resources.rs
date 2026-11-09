//! Application-owned resource paths; Gyroflow Core remains an unmodified Git dependency.

use crate::{BridgeError, BridgeResult};
use cubecl::config::{CubeClRuntimeConfig, RuntimeConfig, cache::CacheConfig};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

/// Immutable paths supplied by the renderer's sandbox-aware entry point.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct RuntimePaths {
    pub data_directory: PathBuf,
    pub gmflow_model: PathBuf,
}

static PATHS: OnceLock<RuntimePaths> = OnceLock::new();
static CONFIGURATION: Mutex<()> = Mutex::new(());

pub(crate) fn configured() -> Option<&'static RuntimePaths> {
    PATHS.get()
}

/// Configures storage without changing the process environment after worker threads have started.
pub(crate) fn configure(paths: RuntimePaths) -> BridgeResult<()> {
    let _guard = CONFIGURATION
        .lock()
        .expect("resource configuration mutex poisoned");
    if let Some(existing) = PATHS.get() {
        return if existing == &paths {
            Ok(())
        } else {
            Err(BridgeError::InvalidInput(
                "Toolbox resource paths were already configured",
            ))
        };
    }
    if !paths.data_directory.is_absolute()
        || !paths.gmflow_model.is_absolute()
        || !paths.gmflow_model.is_file()
    {
        return Err(BridgeError::InvalidInput(
            "the bundled GMFlow model or sandbox storage is unavailable",
        ));
    }
    // Upstream treats an explicit weights path as authoritative: missing/corrupt weights return an
    // error and never enter its download branch. The entry point supplies it before FxPlug starts.
    if std::env::var_os("GYROFLOW_GMFLOW_WEIGHTS").as_deref()
        != Some(paths.gmflow_model.as_os_str())
    {
        return Err(BridgeError::InvalidInput(
            "the renderer must configure its bundled model before starting FxPlug",
        ));
    }
    if std::env::var("GYROFLOW_GMFLOW_DEVICE").is_ok_and(|value| value.eq_ignore_ascii_case("any"))
    {
        return Err(BridgeError::InvalidInput(
            "software GPU adapters are not supported",
        ));
    }
    std::fs::create_dir_all(&paths.data_directory)?;
    let mut configuration = CubeClRuntimeConfig::default();
    configuration.environment.path = CacheConfig::Directory(paths.data_directory.join("GPU Cache"));
    if !CubeClRuntimeConfig::try_set(configuration) {
        return Err(BridgeError::InvalidInput(
            "configure the GPU cache before starting analysis",
        ));
    }
    PATHS
        .set(paths)
        .map_err(|_| BridgeError::InvalidInput("Toolbox resource configuration changed"))
}
