//! Resolves external motion sources once, then embeds their data for sandboxed rendering.

use crate::{BridgeError, BridgeResult, new_manager, project};
use gyroflow_core::{StabilizationManager, filesystem};
use serde_json::Value;
use std::path::{Path, PathBuf};

/// Missing sandbox access is recoverable by selecting the source in a native open panel.
#[derive(Debug)]
pub(crate) enum ImportedProject {
    Ready { project: String },
    NeedsMotion { path: PathBuf },
}

/// Imports a selected project without changing its file or applying saved Toolbox defaults.
/// `motion_path` is an explicit replacement selected by the user, not the FCP timeline media.
pub(crate) fn import_file(
    project_path: &Path,
    motion_path: Option<&Path>,
) -> BridgeResult<ImportedProject> {
    let source = std::fs::read_to_string(project_path)?;
    let mut document: Value = serde_json::from_str(&source)?;
    if !document.is_object() {
        return Err(BridgeError::InvalidInput("project must be a JSON object"));
    }
    let project_url = file_url(project_path)?;
    let manager = new_manager();

    if StabilizationManager::project_has_motion_data(source.as_bytes()) {
        project::import_at_url(&manager, &source, Some(&project_url))?;
        require_motion(&manager)?;
        // Preserve existing embedded projects exactly, including their custom metadata.
        return Ok(ImportedProject::Ready { project: source });
    }

    let video_reference = document["videofile"].as_str().unwrap_or_default();
    let motion_reference = document["gyro_source"]["filepath"]
        .as_str()
        .filter(|path| !path.is_empty())
        .unwrap_or(video_reference);
    if motion_reference.is_empty() {
        return Err(BridgeError::InvalidInput(
            "This project has no embedded motion data or source file reference.",
        ));
    }
    let resolved_motion = match motion_path {
        Some(path) => path.to_owned(),
        None => resolve_reference(motion_reference, project_path)?,
    };
    if !is_readable_file(&resolved_motion) {
        return Ok(ImportedProject::NeedsMotion {
            path: resolved_motion,
        });
    }

    let motion_url = file_url(&resolved_motion)?;
    let video_url = if motion_reference == video_reference {
        motion_url.clone()
    } else if video_reference.is_empty() {
        String::new()
    } else {
        file_url(&resolve_reference(video_reference, project_path)?)?
    };
    document["videofile"] = video_url.into();
    // An old application's bookmark must not override the file authorized in this sandbox.
    document
        .as_object_mut()
        .expect("validated object")
        .remove("videofile_bookmark");
    if document["gyro_source"].is_null() {
        document["gyro_source"] = serde_json::json!({});
    }
    let gyro_source = document["gyro_source"]
        .as_object_mut()
        .ok_or(BridgeError::InvalidInput(
            "project motion source must be a JSON object",
        ))?;
    gyro_source.insert("filepath".into(), motion_url.into());
    gyro_source.remove("filepath_bookmark");

    let relocated = serde_json::to_string(&document)?;
    project::import_at_url(&manager, &relocated, Some(&project_url))?;
    require_motion(&manager)?;
    Ok(ImportedProject::Ready {
        project: project::export_preserving_metadata(&manager, &source)?,
    })
}

fn require_motion(manager: &StabilizationManager) -> BridgeResult<()> {
    if project::has_motion(manager) {
        Ok(())
    } else {
        Err(BridgeError::InvalidInput(
            "No usable motion data was found. Select the original recording or motion-data file used by this project.",
        ))
    }
}

fn file_url(path: &Path) -> BridgeResult<String> {
    let absolute = std::path::absolute(path)?;
    let path = absolute.to_str().ok_or(BridgeError::InvalidInput(
        "project and media paths must be valid UTF-8",
    ))?;
    Ok(filesystem::path_to_url(path))
}

fn is_readable_file(path: &Path) -> bool {
    std::fs::File::open(path)
        .and_then(|file| file.metadata())
        .is_ok_and(|metadata| metadata.is_file())
}

/// Prefer the original source, then a relative path, then the same filename beside the project.
fn resolve_reference(reference: &str, project_path: &Path) -> BridgeResult<PathBuf> {
    let path = if reference.starts_with("file://") {
        filesystem::url_to_path(reference)
    } else if reference.contains("://") {
        return Err(BridgeError::InvalidInput(
            "project media must be a local file",
        ));
    } else {
        reference.to_owned()
    };
    // Gyroflow projects move between Windows and macOS. Normalize before extracting
    // the filename; converting a Windows drive path to a macOS file URL loses it.
    let normalized = path.replace('\\', "/");
    let source_path = Path::new(&normalized);
    if source_path.is_absolute() && is_readable_file(source_path) {
        return Ok(source_path.to_owned());
    }
    let folder = project_path.parent().unwrap_or_else(|| Path::new("."));
    let relative = folder.join(source_path);
    if !source_path.is_absolute() && is_readable_file(&relative) {
        return Ok(relative);
    }
    let filename = source_path.file_name().ok_or(BridgeError::InvalidInput(
        "project media reference has no filename",
    ))?;
    Ok(folder.join(filename))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn moved_projects_resolve_cross_platform_names_without_losing_spaces() {
        let project = Path::new("/missing/project/Movie.gyroflow");
        for reference in [
            "E:/clips/GoPro Hero 6.MP4",
            r"E:\clips\GoPro Hero 6.MP4",
            "file:///E:/clips/GoPro%20Hero%206.MP4",
            "/old/media/GoPro Hero 6.MP4",
            "GoPro Hero 6.MP4",
        ] {
            assert_eq!(
                resolve_reference(reference, project).unwrap(),
                Path::new("/missing/project/GoPro Hero 6.MP4"),
                "reference {reference}"
            );
        }
    }

    #[test]
    fn remote_and_empty_references_are_rejected() {
        for reference in ["https://example.com/video.mp4", "", "/"] {
            assert!(resolve_reference(reference, Path::new("/project.gyroflow")).is_err());
        }
    }
}
