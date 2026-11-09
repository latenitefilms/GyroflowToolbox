#!/bin/bash
set -euo pipefail
repository_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_directory"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gyroflow-compatibility.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
    -I Source/Gyroflow/Plugin -I Source/Frameworks/gyroflow/inc \
    Source/Gyroflow/Plugin/GyroflowParameters.m Tests/Compatibility/ParametersTests.m \
    -o "$test_directory/parameters-tests"
"$test_directory/parameters-tests" Tests/Compatibility/Fixtures/v1.3.5-parameters.archive
python3 Tests/Compatibility/check_identifiers.py

