#!/bin/bash

set -eu
set -o pipefail

export SCRIPT_HOME ; SCRIPT_HOME="$(dirname "$(greadlink -f "$0")")"
export REPO_HOME ; REPO_HOME="$(greadlink -f "${SCRIPT_HOME}/../")"

cd "${REPO_HOME}/Source/Frameworks/gyroflow"
#~/.cargo/bin/cargo clean
~/.cargo/bin/cargo update
~/.cargo/bin/cargo build --release --target x86_64-apple-darwin
~/.cargo/bin/cargo build --release --target aarch64-apple-darwin
lipo -create -output "${REPO_HOME}/Source/Frameworks/gyroflow/target/libgyroflow_toolbox.dylib" "${REPO_HOME}/Source/Frameworks/gyroflow/target/x86_64-apple-darwin/release/libgyroflow_toolbox.dylib" "${REPO_HOME}/Source/Frameworks/gyroflow/target/aarch64-apple-darwin/release/libgyroflow_toolbox.dylib"
/bin/mv "${REPO_HOME}/Source/Frameworks/gyroflow/target/libgyroflow_toolbox.dylib" "${REPO_HOME}/Source/Frameworks/gyroflow/binary/libgyroflow_toolbox.dylib"
cd "${REPO_HOME}/Source/Frameworks/gyroflow/binary"
/usr/bin/install_name_tool -id "@rpath/libgyroflow_toolbox.dylib" libgyroflow_toolbox.dylib