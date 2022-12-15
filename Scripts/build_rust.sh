#!/bin/bash

set -eu
set -o pipefail

cd ~/Documents/GitHub/GyroflowForFinalCutPro/Source/Frameworks/gyroflow
~/.cargo/bin/cargo update
~/.cargo/bin/cargo build --release
/bin/mv ~/Documents/GitHub/GyroflowForFinalCutPro/Source/Frameworks/gyroflow/target/release/libgyroflow.dylib ~/Documents/GitHub/GyroflowForFinalCutPro/Source/Frameworks/gyroflow/binary/libgyroflow.dylib
cd ~/Documents/GitHub/GyroflowForFinalCutPro/Source/Frameworks/gyroflow/binary
/usr/bin/install_name_tool -id "@rpath/libgyroflow.dylib" libgyroflow.dylib