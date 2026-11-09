"""Protect the identities used by saved Final Cut Pro effects."""
import json
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
fixture = json.loads((pathlib.Path(__file__).parent / "Fixtures/v1.3.5-identifiers.json").read_text())
constants = (ROOT / "Source/Frameworks/gyroflow/inc/gyroflow_parameters.h").read_text()
identifiers = dict(re.findall(r"(kCB_\w+)\s*=\s*(\d+)", constants))
for name, value in fixture["parameters"].items():
    assert identifiers.get(name) == value, f"Saved parameter changed: {name}"
assert len(identifiers.values()) == len(set(identifiers.values())), "Duplicate parameter IDs"
with (ROOT / "Source/Gyroflow/Plugin/Info.plist").open("rb") as source:
    info = plistlib.load(source)
assert info["ProPlugPlugInList"][0]["uuid"] == fixture["plugin_uuid"]
assert info["ProPlugPlugInGroupList"][0]["uuid"] == fixture["group_uuid"]
template = ET.parse(ROOT / "Source/Gyroflow/Wrapper Application/Resources/Motion Templates/Gyroflow Toolbox/Gyroflow Toolbox.moef")
published = {(node.get("object"), node.get("channel")) for node in template.findall(".//publishSettings/target")}
assert set(map(tuple, fixture["published_channels"])).issubset(published)
print("PASS: legacy parameter IDs, plugin UUIDs, and published Motion channels")

