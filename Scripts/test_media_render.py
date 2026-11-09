#!/usr/bin/env python3
"""Decode camera fixtures with local FFmpeg and render them through the Metal test harness."""
import argparse
import json
import os
import pathlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--projects", type=pathlib.Path, required=True)
parser.add_argument("--output", type=pathlib.Path, required=True)
parser.add_argument("--iterations", type=int, default=100)
arguments = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
arguments.output.mkdir(parents=True, exist_ok=True)
library = pathlib.Path(os.environ.get("GYROFLOW_LIBRARY_DIRECTORY", root / "Source/Frameworks/gyroflow/binary"))
executable = arguments.output / "media-render-tests"
subprocess.run(["xcrun", "clang", "-fobjc-arc", "-O2", "-Wall", "-Wextra", "-Werror",
    "-framework", "Foundation", "-framework", "Metal", "-I", str(root / "Source/Frameworks/gyroflow/inc"),
    "-L", str(library), "-lgyroflow_toolbox", f"-Wl,-rpath,{library}",
    str(root / "Tests/Compatibility/MediaRenderTests.m"), "-o", str(executable)], check=True)
reports = []
for source in sorted(arguments.directory.glob("*.MP4")):
    project = arguments.projects / (source.name + ".gyroflow")
    document = json.loads(project.read_text())
    info = document["video_info"]
    width, height = info["width"], info["height"]
    frame = round(info["fps"] * min(5.0, info["duration_ms"] / 2000.0))
    seconds = frame / info["fps"]
    input_pixels = arguments.output / (source.stem + "-input.bgra")
    output_pixels = arguments.output / (source.stem + "-output.bgra")
    subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-ss", str(seconds), "-noautorotate",
        "-i", str(source), "-frames:v", "1", "-pix_fmt", "bgra", "-f", "rawvideo", str(input_pixels)], check=True)
    result = subprocess.run([str(executable), str(project), str(input_pixels), str(output_pixels),
        str(width), str(height), str(round(seconds * 1_000_000)), str(arguments.iterations)],
        check=True, text=True, capture_output=True)
    report = json.loads(result.stdout.strip().splitlines()[-1])
    report.update(file=source.name, width=width, height=height, timestamp_seconds=seconds)
    reports.append(report)
    print(json.dumps(report), flush=True)
    for pixels, suffix in [(input_pixels, "input"), (output_pixels, "output")]:
        subprocess.run(["ffmpeg", "-v", "error", "-nostdin", "-y", "-f", "rawvideo", "-pixel_format", "bgra",
            "-video_size", f"{width}x{height}", "-i", str(pixels), "-frames:v", "1", "-vf", "scale=960:-2",
            str(arguments.output / (source.stem + f"-{suffix}.png"))], check=True)
        pixels.unlink()
(arguments.output / "report.json").write_text(json.dumps(reports, indent=2) + "\n")
