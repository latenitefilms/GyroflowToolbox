#!/usr/bin/env python3
"""Exercise preset and default persistence through the Rust ABI in isolated storage."""
import argparse
import ctypes
import json
import os
import pathlib
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--clip", type=pathlib.Path, help="Also verify defaults on a real media import")
arguments = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
model = root / "Source/Gyroflow/Plugin/Resources/Models/gmflow-scale2-regrefine6.bpk"
os.environ["GYROFLOW_GMFLOW_WEIGHTS"] = str(model)
os.environ["GYROFLOW_GMFLOW_DEVICE"] = "hardware"
library = ctypes.CDLL(str(root / "Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"))
library.freeCString.argtypes = [ctypes.c_void_p]
library.freeCString.restype = None
for name, count in {"configureToolboxResources": 2, "toolboxCommand": 4,
                    "getPluginParameterDefinitions": 0, "importMediaFile": 1}.items():
    function = getattr(library, name)
    function.argtypes = [ctypes.c_char_p] * count
    function.restype = ctypes.c_void_p


def owned(name, *values):
    pointer = getattr(library, name)(*(value.encode() for value in values))
    assert pointer, name
    try:
        return json.loads(ctypes.string_at(pointer))
    finally:
        library.freeCString(pointer)


definitions = owned("getPluginParameterDefinitions")
values = {str(item["id"]): item["default"] for item in definitions
          if item["kind"] in ("slider", "menu", "toggle")}
values["100"] = 1.42
project = json.loads((root / "Tests/Compatibility/Fixtures/identity.gyroflow").read_text())
project["offsets"] = {"0": 12.5}
snapshot = [2, 0.0, [[item["id"], [[0, values[str(item["id"])]]]]
                     for item in definitions if "keyframe" in item], values]


def command(action, source=project, **request):
    response = owned("toolboxCommand", json.dumps(source), json.dumps(snapshot),
                     json.dumps(values), json.dumps(dict(action=action, **request)))
    assert response["ok"], response
    return response["result"]


with tempfile.TemporaryDirectory(prefix="gyroflow-preset-tests-") as storage:
    assert owned("configureToolboxResources", storage, str(model))["ok"]
    name = "Handheld / 镜头"
    command("save_preset", name=name)
    assert command("list_presets")["names"] == [name]
    assert command("save_preset", name=name)["exists"]
    command("save_preset", name=name, replace=True)
    target = json.loads(json.dumps(project))
    target["offsets"] = {"0": -7.25}
    recalled = json.loads(command("apply_preset", source=target, name=name)["project"])
    assert recalled["offsets"] == target["offsets"], recalled["offsets"]
    assert all(keyframe["value"] == 1.42 for keyframe in recalled["keyframes"]["Fov"].values())
    assert recalled["keyframes"]["Fov"], "Preset lost the saved Inspector animation"
    files = list((pathlib.Path(storage) / "Presets").glob("*.gyroflow"))
    assert len(files) == 1
    saved = json.loads(files[0].read_text())
    assert "video_info" not in saved and "offsets" not in saved
    assert "calibration_data" in saved and "keyframes" in saved
    command("save_default")
    default = json.loads((pathlib.Path(storage) / "Presets/default.gyroflow").read_text())
    assert default["stabilization"]["fov"] == 1.42
    assert "keyframes" not in default and "calibration_data" not in default
    if arguments.clip:
        imported = owned("importMediaFile", str(arguments.clip.resolve()))
        assert imported["stabilization"]["fov"] == 1.42
        assert imported["video_info"]["width"] > 0
    command("reset_default")
    assert not (pathlib.Path(storage) / "Presets/default.gyroflow").exists()
print("PASS: named preset save/recall, overwrite handling, source offset preservation, and saved defaults")
