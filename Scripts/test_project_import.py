#!/usr/bin/env python3
"""Exercise relocated legacy projects through the Rust ABI without changing camera fixtures."""
import argparse
import ctypes
import json
import pathlib
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=pathlib.Path)
    parser.add_argument("--library", type=pathlib.Path)
    arguments = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    library_path = arguments.library or root / "Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"
    library = ctypes.CDLL(str(library_path.resolve()))
    library.freeCString.argtypes = [ctypes.c_void_p]
    library.trashCache.restype = None

    def call(name, *values):
        function = getattr(library, name)
        function.argtypes = [ctypes.c_char_p] * len(values)
        function.restype = ctypes.c_void_p
        pointer = function(*(str(value).encode() for value in values))
        assert pointer, f"{name} returned null"
        try:
            return ctypes.string_at(pointer).decode()
        finally:
            library.freeCString(pointer)

    original = arguments.project.read_text()
    document = json.loads(original)
    media_name = document["gyro_source"]["filepath"].replace("\\", "/").split("/")[-1]
    media = arguments.project.resolve().with_name(media_name)
    assert media.is_file(), f"Missing camera fixture: {media}"

    with tempfile.TemporaryDirectory(prefix="gyroflow-project-import-") as directory:
        temporary = pathlib.Path(directory)
        project_path = temporary / arguments.project.name
        project_path.write_text(original)

        def import_project(motion_path=""):
            # The old host only inspected JSON, losing the project's location.
            # Keep that path available to demonstrate the original regression.
            if not hasattr(library, "importGyroflowProjectFile"):
                contains_motion = call("doesGyroflowProjectContainStabilisationData", project_path.read_text())
                assert contains_motion == "YES", "Legacy project rejected: source media was not resolved beside the project"
            return json.loads(call("importGyroflowProjectFile", project_path, motion_path))

        sibling = temporary / media_name
        sibling.symlink_to(media)
        response = import_project()
        assert response["ok"], response
        assert response["result"]["status"] == "ready", response
        embedded = response["result"]["project"]
        imported = json.loads(embedded)
        assert call("doesGyroflowProjectContainStabilisationData", embedded) == "YES"
        assert imported["offsets"] == document["offsets"], "Saved synchronization offsets changed"
        assert imported["calibration_data"]["identifier"] == document["calibration_data"]["identifier"]
        assert imported["stabilization"]["fov"] == document["stabilization"]["fov"]
        old_smoothing = {parameter["name"]: parameter["value"] for parameter in document["stabilization"]["smoothing_params"]}
        new_smoothing = {parameter["name"]: parameter["value"] for parameter in imported["stabilization"]["smoothing_params"]}
        assert new_smoothing["smoothness"] == old_smoothing["smoothness"]
        assert imported["gyro_source"]["file_metadata"], "Motion metadata must be embedded for offline rendering"

        sibling.unlink()
        library.trashCache()
        project_path.write_text(embedded)
        response = import_project()
        assert response["ok"] and response["result"]["status"] == "ready", response
        assert call("doesGyroflowProjectContainStabilisationData", response["result"]["project"]) == "YES"

        project_path.write_text(original)
        response = import_project()
        assert response["ok"] and response["result"]["status"] == "needs_motion", response
        assert pathlib.Path(response["result"]["path"]) == sibling, response
        response = import_project(media)
        assert response["ok"] and response["result"]["status"] == "ready", response
        assert json.loads(response["result"]["project"])["offsets"] == document["offsets"]

        # Windows separators and separate motion sources must not resolve to the wrong clip.
        document["videofile"] = "C:\\old clips\\different video.MP4"
        document["gyro_source"]["filepath"] = "C:\\old clips\\" + media_name
        project_path.write_text(json.dumps(document))
        response = import_project()
        assert response["ok"] and response["result"]["status"] == "needs_motion", response
        assert pathlib.Path(response["result"]["path"]) == sibling, response
        sibling.symlink_to(media)
        response = import_project()
        assert response["ok"] and response["result"]["status"] == "ready", response

        project_path.write_text("invalid project")
        assert not import_project()["ok"], "Invalid JSON must fail without poisoning later imports"
        raw_media = call("importMediaFile", media)
        assert raw_media != "FAIL"
        assert call("doesGyroflowProjectContainStabilisationData", raw_media) == "YES"
        project_path.write_text(original)
        no_motion = temporary / "no motion.txt"
        no_motion.write_text("This file has no camera telemetry.")
        assert not import_project(no_motion)["ok"], "An unrelated file cannot complete project recovery"

    assert arguments.project.read_text() == original, "The source project must remain unchanged"
    print("PASS: legacy relocation, saved settings, embedded/offline motion, source recovery and failed-import isolation")


if __name__ == "__main__":
    main()
