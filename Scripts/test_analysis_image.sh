#!/bin/bash
set -euo pipefail
repository_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_directory"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gyroflow-analysis-image.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=13.0 \
    -framework Foundation -framework Metal -framework CoreImage -framework CoreGraphics \
    -I Source/Gyroflow/Plugin Source/Gyroflow/Plugin/GyroflowAnalysisImage.m \
    Tests/Compatibility/AnalysisImageTests.m -o "$test_directory/analysis-image-tests"
"$test_directory/analysis-image-tests"
