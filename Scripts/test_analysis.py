#!/usr/bin/env python3
"""Exercise the Rust GPU analysis ABI outside Final Cut Pro.

Requires a Metal GPU. --clip uses ffmpeg only as a test decoder; it is not an app dependency.
The application itself receives its frames from FxPlug and uses the tested Metal converter.
"""
import argparse
import ctypes
import hashlib
import json
import os
import pathlib
import resource
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--gmflow", action="store_true")
parser.add_argument("--ignore-motion", action="store_true", help="Test optical-only stabilisation with recorded gyro data ignored")
parser.add_argument("--library", type=pathlib.Path, help="Use a development dylib without replacing the release library")
parser.add_argument("--clip", type=pathlib.Path)
parser.add_argument("--mode", choices=["optical", "synchronize", "lens_delay"], default="optical")
parser.add_argument("--seconds", type=float, default=3.0)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
model = root / "Source/Gyroflow/Plugin/Resources/Models/gmflow-scale2-regrefine6.bpk"
assert hashlib.sha256(model.read_bytes()).hexdigest() == "8d51cb8eaf2c56b6f727ef83534616c4dd98f4ce7ff9b5fa812c132c44db9db7"
# Set upstream overrides before loading the dylib or starting its worker threads.
os.environ["GYROFLOW_GMFLOW_WEIGHTS"] = str(model)
os.environ["GYROFLOW_GMFLOW_DEVICE"] = "hardware"
library = ctypes.CDLL(str(args.library or root / "Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"))
library.freeCString.argtypes = [ctypes.c_void_p]
string = ctypes.c_char_p
for name, arguments in {
    "configureToolboxResources": [string, string], "getPluginParameterDefinitions": [],
    "beginToolboxAnalysis": [string, string, string, string],
    "feedToolboxAnalysis": [ctypes.c_uint64, ctypes.c_int64, ctypes.c_uint32, ctypes.c_uint32,
                            ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t],
    "finishToolboxAnalysis": [ctypes.c_uint64],
    "toolboxAnalysisFrameLayout": [ctypes.c_uint64, ctypes.c_uint32, ctypes.c_uint32],
    "toolboxCommand": [string, string, string, string],
    "importMediaFile": [string], "doesGyroflowProjectContainStabilisationData": [string],
}.items():
    function = getattr(library, name)
    function.argtypes = arguments
    function.restype = ctypes.c_void_p
for name in ["cancelToolboxAnalysis", "releaseToolboxAnalysis"]:
    getattr(library, name).argtypes = [ctypes.c_uint64]
    getattr(library, name).restype = None


def owned(name, *arguments):
    pointer = getattr(library, name)(*arguments)
    assert pointer, name
    try:
        return ctypes.string_at(pointer).decode()
    finally:
        library.freeCString(pointer)


def call(name, *arguments):
    response = json.loads(owned(name, *arguments))
    assert response["ok"], f"{name}: {response.get('error')}"
    return response["result"]


def encoded(value):
    return json.dumps(value, separators=(",", ":")).encode()


cache = pathlib.Path(tempfile.gettempdir()) / "gyroflow-toolbox-analysis-tests"
call("configureToolboxResources", str(cache).encode(), str(model).encode())
library.startLogger.argtypes = [string]
log_path = cache / f"{args.mode}-{'gmflow' if args.gmflow else 'klt'}-{os.getpid()}.log"
library.startLogger(str(log_path).encode())
values = {str(item["id"]): item["default"] for item in json.loads(owned("getPluginParameterDefinitions"))
          if item["kind"] in ("slider", "menu", "toggle")}
values["701"] = int(args.gmflow)
values["702"] = args.ignore_motion

if args.clip:
    project = owned("importMediaFile", str(args.clip.resolve()).encode())
    assert project != "FAIL", "Media import failed"
    document = json.loads(project)
    info = document["video_info"]
    if not document.get("calibration_data", {}).get("calib_dimension", {}).get("w"):
        project = call("toolboxCommand", project.encode(), b"", b"{}",
                       encoded({"action": "focal_length", "focal_length": 24.0}))["project"]
    scale = min(1.0, 960.0 / max(info["width"], info["height"]))
    width, height = round(info["width"] * scale), round(info["height"] * scale)
    duration_ms = min(args.seconds * 1000, info["duration_ms"])
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-read_intervals", f"%+{args.seconds}",
        "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", str(args.clip)], check=True, capture_output=True)
    timestamps = [round(float(frame["best_effort_timestamp_time"]) * 1_000_000)
                  for frame in json.loads(probe.stdout)["frames"]]
    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-noautorotate", "-i", str(args.clip), "-t", str(args.seconds),
        "-vf", f"scale={width}:{height}", "-pix_fmt", "gray", "-fps_mode", "passthrough", "-f", "rawvideo", "-"], stdout=subprocess.PIPE)

    def frames():
        try:
            for timestamp in timestamps:
                pixels = decoder.stdout.read(width * height)
                if not pixels:
                    break
                assert len(pixels) == width * height
                yield timestamp, pixels
        finally:
            decoder.stdout.close()
            if decoder.poll() is None:
                decoder.terminate()
            decoder.wait()
else:
    width, height, count = 320, 180, 30
    duration_ms = count / 30 * 1000
    document = json.loads((root / "Tests/Compatibility/Fixtures/identity.gyroflow").read_text())
    document["video_info"] = dict(width=width, height=height, fps=30.0, num_frames=count, duration_ms=duration_ms)
    lens = document["calibration_data"]
    lens["calib_dimension"] = lens["orig_dimension"] = dict(w=width, h=height)
    lens["fisheye_params"]["camera_matrix"] = [[width, 0, width / 2], [0, width, height / 2], [0, 0, 1]]
    project = json.dumps(document)
    # A deterministic textured scene translated right by one pixel per frame.
    texture = bytes(40 + ((column // 6 + row // 6) % 2) * 140 + (((column // 6 * 73856093 ^ row // 6 * 19349663) >> 7) % 40)
                    for row in range(height) for column in range(width + count))

    def frames():
        for frame in range(count):
            pixels = b"".join(texture[row * (width + count) + frame:row * (width + count) + frame + width]
                              for row in range(height))
            yield round(frame / 30 * 1_000_000), pixels


started = time.monotonic()
session = call("beginToolboxAnalysis", project.encode(), project.encode(), encoded(values),
               encoded(dict(mode=args.mode, start_ms=0.0, end_ms=duration_ms)))["session"]
try:
    layout = call("toolboxAnalysisFrameLayout", session, width, height)
    assert layout["width"] <= 960 and layout["height"] <= 960
    fed = 0
    for timestamp, pixels in frames():
        call("feedToolboxAnalysis", session, timestamp, width, height, width, pixels, len(pixels))
        fed += 1
    result = call("finishToolboxAnalysis", session)
    saved = result.pop("project")
    if args.mode == "optical":
        assert owned("doesGyroflowProjectContainStabilisationData", saved.encode()) == "YES"
        assert json.loads(saved)["gyro_source"].get("optical_correction")
    print(json.dumps({"tracker": "GMFlow" if args.gmflow else "KLT", "frames_fed": fed,
                      "elapsed_seconds": round(time.monotonic() - started, 3),
                      "peak_rss_mib": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024**2, 1),
                      "result": result, "log": str(log_path)}, indent=2), flush=True)
finally:
    library.releaseToolboxAnalysis(session)
# An interrupted job must not publish partial data or retain a session slot.
values["170"] = 270.0
session = call("beginToolboxAnalysis", project.encode(), project.encode(), encoded(values), encoded({"mode": "optical"}))["session"]
portrait = call("toolboxAnalysisFrameLayout", session, height, width)
assert portrait["rotation"] == 270.0 and portrait["crop"] == [0, 0, height, width], portrait
library.cancelToolboxAnalysis(session)
response = json.loads(owned("finishToolboxAnalysis", session))
assert not response["ok"] and "cancelled" in response["error"]
library.releaseToolboxAnalysis(session)
library.releaseToolboxAnalysis(session)
print("PASS: analysis result serialization, inspector rotation, cancellation, and idempotent release")
