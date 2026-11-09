//! Complete inspector catalog and value validation. The native host only adapts FxPlug APIs.

use crate::{BridgeError, BridgeResult, controls};
use gyroflow_core::keyframes::KeyframeType;
use serde_json::{Value, json};
use std::sync::LazyLock;

#[derive(Debug, Clone, Copy)]
pub(crate) enum Visibility {
    Normal,
    Hidden,
    Disabled,
}

#[derive(Debug, Clone)]
enum Kind {
    Group {
        collapsed: bool,
    },
    EndGroup,
    Custom,
    Button(&'static str),
    Slider {
        default: f64,
        minimum: f64,
        maximum: f64,
        delta: f64,
    },
    Toggle(bool),
    Menu {
        default: u32,
        entries: &'static [&'static str],
    },
    Text(&'static str),
}

#[derive(Debug, Clone)]
pub(crate) struct Parameter {
    identifier: u32,
    name: &'static str,
    kind: Kind,
    visibility: Visibility,
    animated: bool,
    symbol: Option<&'static str>,
    archive: Option<&'static str>,
    keyframe: Option<(KeyframeType, f64)>,
}
impl Parameter {
    fn new(identifier: u32, name: &'static str, kind: Kind) -> Self {
        Self {
            identifier,
            name,
            kind,
            visibility: Visibility::Normal,
            animated: false,
            symbol: None,
            archive: None,
            keyframe: None,
        }
    }
    pub(crate) fn symbol(mut self, symbol: &'static str) -> Self {
        self.symbol = Some(symbol);
        self
    }
    fn archive(mut self, key: &'static str) -> Self {
        self.archive = Some(key);
        self
    }
    pub(crate) fn animated(mut self, animated: bool) -> Self {
        self.animated = animated;
        self
    }
    pub(crate) fn json(&self) -> Value {
        let mut value = json!({"id": self.identifier, "name": self.name, "animated": self.animated,
            "hidden": matches!(self.visibility, Visibility::Hidden), "disabled": matches!(self.visibility, Visibility::Disabled)});
        if let Some(symbol) = self.symbol {
            value["symbol"] = symbol.into();
        }
        if let Some(archive) = self.archive {
            value["archive"] = archive.into();
        }
        if let Some((parameter, scale)) = self.keyframe {
            value["keyframe"] = json!(parameter);
            value["scale"] = scale.into();
        }
        match self.kind {
            Kind::Group { collapsed } => {
                value["kind"] = "group".into();
                value["collapsed"] = collapsed.into();
            }
            Kind::EndGroup => return json!({"kind": "end-group"}),
            Kind::Custom => {
                value["kind"] = "custom".into();
                value["default"] = 0.into();
            }
            Kind::Button(title) => {
                value["kind"] = "custom".into();
                value["default"] = 0.into();
                value["button_title"] = title.into();
            }
            Kind::Slider {
                default,
                minimum,
                maximum,
                delta,
            } => {
                value["kind"] = "slider".into();
                value["default"] = default.into();
                value["min"] = minimum.into();
                value["max"] = maximum.into();
                value["delta"] = delta.into();
            }
            Kind::Toggle(default) => {
                value["kind"] = "toggle".into();
                value["default"] = default.into();
            }
            Kind::Menu { default, entries } => {
                value["kind"] = "menu".into();
                value["default"] = default.into();
                value["entries"] = json!(entries);
            }
            Kind::Text(default) => {
                value["kind"] = "text".into();
                value["default"] = default.into();
            }
        }
        value
    }
    pub(crate) fn validate_value(&self, values: &Value) -> BridgeResult<()> {
        let value = &values[self.identifier.to_string()];
        let valid = match self.kind {
            Kind::Slider {
                minimum, maximum, ..
            } => value
                .as_f64()
                .is_some_and(|value| value.is_finite() && (minimum..=maximum).contains(&value)),
            Kind::Toggle(_) => value.is_boolean(),
            Kind::Menu { entries, .. } => value
                .as_u64()
                .is_some_and(|value| value < entries.len() as u64),
            _ => true,
        };
        if !valid {
            return Err(BridgeError::InvalidInput(
                "missing or out-of-range inspector value",
            ));
        }
        Ok(())
    }
}

pub(crate) fn group(identifier: u32, name: &'static str, collapsed: bool) -> Parameter {
    Parameter::new(identifier, name, Kind::Group { collapsed })
}
pub(crate) fn end_group() -> Parameter {
    Parameter::new(0, "", Kind::EndGroup)
}
pub(crate) fn slider(
    identifier: u32,
    name: &'static str,
    default: f64,
    minimum: f64,
    maximum: f64,
    delta: f64,
) -> Parameter {
    Parameter::new(
        identifier,
        name,
        Kind::Slider {
            default,
            minimum,
            maximum,
            delta,
        },
    )
    .animated(true)
}
pub(crate) fn toggle(identifier: u32, name: &'static str, default: bool) -> Parameter {
    Parameter::new(identifier, name, Kind::Toggle(default))
}
pub(crate) fn menu(
    identifier: u32,
    name: &'static str,
    default: u32,
    entries: &'static [&'static str],
) -> Parameter {
    Parameter::new(identifier, name, Kind::Menu { default, entries })
}
fn custom(identifier: u32, name: &'static str) -> Parameter {
    Parameter::new(identifier, name, Kind::Custom)
}
pub(crate) fn button(identifier: u32, title: &'static str) -> Parameter {
    Parameter::new(identifier, "", Kind::Button(title))
}
fn text(
    identifier: u32,
    name: &'static str,
    default: &'static str,
    visibility: Visibility,
) -> Parameter {
    let mut parameter = Parameter::new(identifier, name, Kind::Text(default));
    parameter.visibility = visibility;
    parameter
}

static CATALOG: LazyLock<Vec<Parameter>> = LazyLock::new(catalog);

fn catalog() -> Vec<Parameter> {
    let mut parameters = legacy_catalog();
    let insertion = parameters
        .iter()
        .position(|parameter| parameter.identifier == 180)
        .expect("video rotation is a legacy parameter")
        + 1;
    let mut additions = vec![
        toggle(200, "Override Project Zoom and Orientation", false)
            .symbol("kCB_OverrideProjectSettings"),
        slider(210, "Zoom Limit", 130.0, 0.0, 300.0, 1.0).symbol("kCB_ZoomLimit"),
        slider(220, "Additional Pitch", 0.0, -180.0, 180.0, 0.1).symbol("kCB_AdditionalPitch"),
        slider(230, "Additional Yaw", 0.0, -180.0, 180.0, 0.1).symbol("kCB_AdditionalYaw"),
        menu(
            240,
            "Integration Method",
            0,
            &[
                "From Gyroflow Project",
                "None",
                "Complementary",
                "VQF",
                "Simple Gyro",
                "Simple Gyro + Accel",
                "Mahony",
                "Madgwick",
            ],
        )
        .symbol("kCB_IntegrationMethod"),
        menu(
            250,
            "Interpolation",
            0,
            &[
                "Lanczos4",
                "RobidouxSharp",
                "Bilinear",
                "Bicubic",
                "Robidoux",
                "Mitchell",
                "CatmullRom",
            ],
        )
        .symbol("kCB_Interpolation"),
        toggle(260, "Use Gyroflow Keyframes", true).symbol("kCB_UseGyroflowKeyframes"),
    ];
    additions.extend(controls::definitions());
    additions.extend(crate::analysis::definitions());
    additions.extend(crate::presets::definitions());
    parameters.splice(insertion..insertion, additions);
    for (identifier, kind, scale) in [
        (100, KeyframeType::Fov, 1.0),
        (110, KeyframeType::SmoothingParamSmoothness, 1.0),
        (120, KeyframeType::LensCorrectionStrength, 100.0),
        (130, KeyframeType::LockHorizonAmount, 1.0),
        (140, KeyframeType::LockHorizonRoll, 1.0),
        (150, KeyframeType::ZoomingCenterX, 100.0),
        (160, KeyframeType::ZoomingCenterY, 100.0),
        (180, KeyframeType::VideoRotation, 1.0),
        (210, KeyframeType::MaxZoom, 1.0),
        (220, KeyframeType::AdditionalRotationY, 1.0),
        (230, KeyframeType::AdditionalRotationX, 1.0),
    ]
    .into_iter()
    .chain(controls::KEYFRAMES)
    {
        parameters
            .iter_mut()
            .find(|parameter| parameter.identifier == identifier)
            .expect("every keyframe maps to an inspector parameter")
            .keyframe = Some((kind, scale));
    }
    parameters
}

fn legacy_catalog() -> Vec<Parameter> {
    vec![
        group(1, "Gyroflow Toolbox", false).symbol("kCB_TopSection"),
        custom(2, "").symbol("kCB_Header"),
        custom(3, "").symbol("kCB_OpenUserGuide"),
        end_group(),
        group(5, "Import", false).symbol("kCB_ImportSection"),
        custom(10, "Drop Clip Here ➡").symbol("kCB_DropZone"),
        custom(30, "").symbol("kCB_ImportGyroflowProject"),
        custom(25, "").symbol("kCB_LoadLastGyroflowProject"),
        custom(35, "").symbol("kCB_ImportMediaFile"),
        custom(52, "").symbol("kCB_LoadPresetLensProfile"),
        end_group(),
        group(90, "Gyroflow Parameters", false).symbol("kCB_GyroflowParameters"),
        slider(100, "FOV", 1.0, 0.1, 3.0, 0.001)
            .symbol("kCB_FOV")
            .archive("fov"),
        slider(110, "Smoothness", 0.5, 0.01, 3.0, 0.001)
            .symbol("kCB_Smoothness")
            .archive("smoothness"),
        slider(120, "Lens Correction", 100.0, 0.0, 100.0, 0.1)
            .symbol("kCB_LensCorrection")
            .archive("lensCorrection"),
        slider(130, "Horizon Lock", 0.0, 0.0, 100.0, 0.1)
            .symbol("kCB_HorizonLock")
            .archive("horizonLock"),
        slider(140, "Horizon Roll", 0.0, -100.0, 100.0, 0.1)
            .symbol("kCB_HorizonRoll")
            .archive("horizonRoll"),
        slider(150, "Position Offset X", 0.0, -100.0, 100.0, 0.1)
            .symbol("kCB_PositionOffsetX")
            .archive("positionOffsetX"),
        slider(160, "Position Offset Y", 0.0, -100.0, 100.0, 0.1)
            .symbol("kCB_PositionOffsetY")
            .archive("positionOffsetY"),
        slider(170, "Input Rotation", 0.0, -360.0, 360.0, 0.1)
            .symbol("kCB_InputRotation")
            .archive("inputRotation"),
        slider(180, "Video Rotation", 0.0, -360.0, 360.0, 0.1)
            .symbol("kCB_VideoRotation")
            .archive("videoRotation"),
        end_group(),
        group(300, "Tools", false).symbol("kCB_ToolsSection"),
        toggle(310, "Stabilisation Overview", false)
            .symbol("kCB_FieldOfViewOverview")
            .archive("fovOverview"),
        toggle(320, "Disable Gyroflow Stretch", false)
            .symbol("kCB_DisableGyroflowStretch")
            .archive("disableGyroflowStretch"),
        end_group(),
        group(400, "File Management", false).symbol("kCB_FileManagementSection"),
        custom(50, "").symbol("kCB_ReloadGyroflowProject"),
        custom(20, "").symbol("kCB_LaunchGyroflow"),
        custom(51, "").symbol("kCB_ExportGyroflowProject"),
        custom(55, "").symbol("kCB_RevealInFinder"),
        custom(4, "").symbol("kCB_Settings"),
        text(
            40,
            "Loaded Gyroflow Project",
            "NOTHING LOADED",
            Visibility::Disabled,
        )
        .symbol("kCB_LoadedGyroflowProject"),
        end_group(),
        text(500, "Unique Identifier", "", Visibility::Hidden).symbol("kCB_UniqueIdentifier"),
        text(60, "Gyroflow Project Path", "", Visibility::Hidden).symbol("kCB_GyroflowProjectPath"),
        text(70, "Gyroflow Project Bookmark Data", "", Visibility::Hidden)
            .symbol("kCB_GyroflowProjectBookmarkData"),
        text(80, "Gyroflow Project Data", "", Visibility::Hidden).symbol("kCB_GyroflowProjectData"),
        text(510, "Media Path", "", Visibility::Hidden).symbol("kCB_MediaPath"),
        text(520, "Media Bookmark Data", "", Visibility::Hidden).symbol("kCB_MediaBookmarkData"),
    ]
}

pub(crate) fn definitions() -> Value {
    CATALOG.iter().map(Parameter::json).collect()
}
pub(crate) fn keyframed() -> impl Iterator<Item = (u32, KeyframeType, f64)> {
    CATALOG.iter().filter_map(|parameter| {
        parameter
            .keyframe
            .map(|(kind, scale)| (parameter.identifier, kind, scale))
    })
}
pub(crate) fn validate(values: &Value) -> BridgeResult<()> {
    if !values.is_object() {
        return Err(BridgeError::InvalidInput(
            "inspector values must be an object",
        ));
    }
    for parameter in CATALOG.iter() {
        parameter.validate_value(values)?;
    }
    Ok(())
}

#[cfg(test)]
pub(crate) fn default_values() -> Value {
    CATALOG
        .iter()
        .filter_map(|parameter| match parameter.kind {
            Kind::Slider { default, .. } => {
                Some((parameter.identifier.to_string(), json!(default)))
            }
            Kind::Toggle(default) => Some((parameter.identifier.to_string(), json!(default))),
            Kind::Menu { default, .. } => Some((parameter.identifier.to_string(), json!(default))),
            _ => None,
        })
        .collect::<serde_json::Map<String, Value>>()
        .into()
}

/// C aliases for native action dispatch, generated from the Rust catalog at build time.
pub(crate) fn constants() -> String {
    let mut header = String::from(
        "// Generated by Scripts/sync_parameters.py from the Rust catalog.\n#ifndef GYROFLOW_PARAMETER_IDS_H\n#define GYROFLOW_PARAMETER_IDS_H\nenum {\n",
    );
    for parameter in CATALOG.iter() {
        if let Some(symbol) = parameter.symbol {
            header.push_str(&format!("    {symbol} = {},\n", parameter.identifier));
        }
    }
    // Reserved in v1.3.5, but never registered with FxPlug. Do not reuse this ID.
    header.push_str("    kCB_VideoSpeed = 190,\n};\n#endif\n");
    header
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn legacy_parameter_contract_is_unchanged() {
        let baseline: Vec<Value> = serde_json::from_str(include_str!(
            "../../../../Tests/Compatibility/Fixtures/v1.3.5-parameter-definitions.json"
        ))
        .unwrap();
        let catalog = definitions();
        for original in baseline {
            let Some(symbol) = original["parameterID"].as_str() else {
                continue;
            };
            let current = catalog
                .as_array()
                .unwrap()
                .iter()
                .find(|parameter| parameter["symbol"].as_str() == Some(symbol))
                .unwrap();
            assert_eq!(current["name"], original["name"], "{symbol}");
            if original["method"] == "addFloatSliderWithName" {
                for (field, previous) in [
                    ("default", "defaultValue"),
                    ("min", "parameterMin"),
                    ("max", "parameterMax"),
                    ("delta", "delta"),
                ] {
                    assert_eq!(
                        current[field].as_f64(),
                        original[previous]
                            .as_str()
                            .and_then(|value| value.parse().ok()),
                        "{symbol}: {field}"
                    );
                }
            }
            let flags = original["parameterFlags"].as_str().unwrap();
            assert_eq!(current["hidden"], flags.contains("HIDDEN"));
            assert_eq!(current["disabled"], flags.contains("DISABLED"));
            if current["kind"] != "group" {
                assert_eq!(current["animated"], !flags.contains("NOT_ANIMATABLE"));
            }
        }
    }
}
