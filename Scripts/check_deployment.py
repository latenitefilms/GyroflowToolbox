#!/usr/bin/env python3
"""Reject a Mach-O dependency whose minimum macOS exceeds the application's target."""
import argparse
import re
import subprocess


def version(value):
    """Compare dotted deployment versions independently of their component count."""
    components = tuple(map(int, value.split(".")))
    return components + (0,) * (3 - len(components))


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--minimum", required=True)
parser.add_argument("binary")
arguments = parser.parse_args()
output = subprocess.run(["xcrun", "vtool", "-show-build", arguments.binary],
                        check=True, text=True, capture_output=True).stdout
minimums = re.findall(r"\bminos\s+([0-9.]+)", output)
if not minimums:
    raise SystemExit(f"error: Cannot verify deployment compatibility: {arguments.binary}")
for minimum in minimums:
    if version(minimum) > version(arguments.minimum):
        raise SystemExit(f"error: {arguments.binary} requires macOS {minimum}; target is {arguments.minimum}")
print(f"Verified macOS {arguments.minimum} compatibility: {arguments.binary}")
