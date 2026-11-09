#!/bin/bash
set -euo pipefail
repository_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_directory"
test_directory="${GYROFLOW_TEST_DIRECTORY:-$(mktemp -d "${TMPDIR:-/tmp}/gyroflow-metal.XXXXXX")}"
mkdir -p "$test_directory"
library_directory="${GYROFLOW_LIBRARY_DIRECTORY:-$repository_directory/Source/Frameworks/gyroflow/binary}"
xcrun clang -fobjc-arc -O2 -Wall -Wextra -Werror -framework Foundation -framework Metal \
    -I Source/Frameworks/gyroflow/inc -L "$library_directory" -lgyroflow_toolbox \
    -Wl,-rpath,"$library_directory" Tests/Compatibility/MetalTests.m -o "$test_directory/metal-tests"
if [[ $# -eq 0 ]]; then set -- 100; fi
"$test_directory/metal-tests" Tests/Compatibility/Fixtures/identity.gyroflow "$@"

