#!/usr/bin/env python3
"""Import local camera fixtures through the shipping Rust ABI; never modify the originals."""
import argparse
import ctypes
import json
import pathlib
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--library", type=pathlib.Path)
arguments = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
library_path = arguments.library or root / "Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"
library = ctypes.CDLL(str(library_path.resolve()))
arguments.output.mkdir(parents=True, exist_ok=True)
library.freeCString.argtypes = [ctypes.c_void_p]
library.startLogger.argtypes = [ctypes.c_char_p]
library.startLogger.restype = None
library.startLogger(str(arguments.output / "import.log").encode())

def call(name, value):
    function = getattr(library, name)
    function.argtypes = [ctypes.c_char_p]
    function.restype = ctypes.c_void_p
    pointer = function(value)
    if not pointer:
        raise RuntimeError(f"{name} returned a null pointer")
    try:
        result = ctypes.string_at(pointer)
    finally:
        library.freeCString(pointer)
    if result == b"FAIL":
        raise RuntimeError(f"{name} failed")
    return result

report = []
for path in sorted(arguments.directory.iterdir()):
    if path.suffix.lower() not in {".mp4", ".mov", ".braw", ".r3d"}:
        continue
    started = time.perf_counter()
    try:
        project = call("importMediaFile", str(path.resolve()).encode())
        document = json.loads(project)
        result = {
            "file": path.name,
            "import_seconds": round(time.perf_counter() - started, 3),
            "video": document.get("video_info"),
            "lens": document.get("calibration_data", {}).get("name"),
            "motion": call("doesGyroflowProjectContainStabilisationData", project).decode(),
            "accurate_timestamps": call("hasAccurateTimestamps", project).decode(),
            "lens_loaded": call("isLensProfileLoaded", project).decode(),
            "embedded_project_bytes": len(project),
        }
        (arguments.output / (path.name + ".gyroflow")).write_bytes(project)
        if result["motion"] != "YES":
            result["error"] = "No embedded motion data"
    except (RuntimeError, ValueError) as error:
        result = {"file": path.name, "error": str(error)}
    report.append(result)
    print(json.dumps(result), flush=True)
    library.trashCache()
(arguments.output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
raise SystemExit(any("error" in result for result in report))
