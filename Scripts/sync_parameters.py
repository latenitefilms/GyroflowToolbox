#!/usr/bin/env python3
"""Generate or check additive Motion parameters against the Rust inspector schema."""
import argparse
import ctypes
import html
import pathlib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--write", action="store_true", help="Update the generated part of the template")
arguments = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
library = ctypes.CDLL(str(root / "Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"))
library.getPluginParameterDefinitions.restype = ctypes.c_void_p
library.freeCString.argtypes = [ctypes.c_void_p]
pointer = library.getPluginParameterDefinitions()
try:
    import json
    definitions = json.loads(ctypes.string_at(pointer))
finally:
    library.freeCString(pointer)

# Only the additive controls are regenerated; historical Motion archives remain byte-for-byte intact.
selected = []
groups = []
for definition in definitions:
    kind = definition["kind"]
    if kind == "end-group":
        identifier = groups.pop()
    else:
        identifier = definition["id"]
        if kind == "group":
            groups.append(identifier)
    if 200 <= identifier < 300 or 600 <= identifier < 700:
        selected.append(definition)

library.getParameterConstants.restype = ctypes.c_void_p
pointer = library.getParameterConstants()
try:
    constants = ctypes.string_at(pointer).decode()
finally:
    library.freeCString(pointer)
constants_path = root / "Source/Frameworks/gyroflow/inc/gyroflow_parameters.h"
if arguments.write:
    constants_path.write_text(constants)
elif not constants_path.exists() or constants_path.read_text() != constants:
    raise SystemExit("Generated C parameter IDs are out of date. Run Scripts/sync_parameters.py --write")

start = "\t\t\t\t\t<!-- BEGIN RUST PARAMETERS -->"
end = "\t\t\t\t\t<!-- END RUST PARAMETERS -->"
lines = [start]
level = 5
for definition in selected:
    kind = definition["kind"]
    if kind == "end-group":
        level -= 1
        lines.append("\t" * level + "</parameter>")
        continue
    name = html.escape(definition["name"], quote=True)
    prefix = "\t" * level + f'<parameter name="{name}" id="{definition["id"]}"'
    if kind == "group":
        lines.append(prefix + ' flags="8589938704">')
        level += 1
    else:
        value = definition["default"]
        if isinstance(value, bool):
            value = int(value)
        lines.append(prefix + f' flags="12884901904" default="{value}" value="{value}"/>')
assert level == 5, "Unbalanced inspector groups"
lines.append(end)
generated = "\n".join(lines)
path = root / "Source/Gyroflow/Wrapper Application/Resources/Motion Templates/Gyroflow Toolbox/Gyroflow Toolbox.moef"
template = path.read_text()
if start not in template:
    raise SystemExit("Generated-parameter markers missing from the Motion template")
begin = template.index(start)
finish = template.index(end, begin) + len(end)
updated = template[:begin] + generated + template[finish:]
if arguments.write:
    path.write_text(updated)
elif updated != template:
    raise SystemExit("Motion parameters are out of date. Build Rust, then run Scripts/sync_parameters.py --write")
print("PASS: Motion parameters match the Rust inspector schema")
