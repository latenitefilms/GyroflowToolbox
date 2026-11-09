#!/bin/bash
set -euo pipefail
repository_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_directory"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gyroflow-analysis-actions.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
sdk_frameworks="/Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks"
library_directory="${GYROFLOW_LIBRARY_DIRECTORY:-$repository_directory/Source/Frameworks/gyroflow/binary}"
sources=()
for source in Source/Gyroflow/Plugin/*.m; do
    case "$source" in
        */main.m) continue ;;
        */GyroflowActions.m) source="${GYROFLOW_ACTIONS_SOURCE:-$source}" ;;
        */GyroflowAnalysis.m) source="${GYROFLOW_ANALYSIS_SOURCE:-$source}" ;;
        */GyroflowPlugIn.m) source="${GYROFLOW_PLUGIN_SOURCE:-$source}" ;;
    esac
    sources+=("$source")
done
xcrun clang -fobjc-arc -fmodules -fmodules-cache-path="$test_directory/modules" \
    -Wall -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 \
    -F "$sdk_frameworks" -framework FxPlug -framework PluginManager \
    -framework Foundation -framework AppKit -framework Metal -framework CoreImage \
    -framework AVFoundation -framework Accelerate -framework MetalPerformanceShaders \
    -I Source/Gyroflow/Plugin -I Source/Gyroflow/Shared -I Source/Frameworks/gyroflow/inc \
    -L "$library_directory" -lgyroflow_toolbox -Wl,-rpath,"$library_directory" \
    -Wl,-rpath,/Library/Developer/Frameworks \
    "${sources[@]}" Source/Gyroflow/Shared/GyroflowAlertFactory.m \
    Tests/Compatibility/AnalysisActionTests.m Tests/Compatibility/ImportTests.m \
    -o "$test_directory/analysis-action-tests"
"$test_directory/analysis-action-tests"
