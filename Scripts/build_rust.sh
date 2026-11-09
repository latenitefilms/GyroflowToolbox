#!/bin/bash
# Override GYROFLOW_ARCHS for a single-architecture development build.
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd -- "${script_directory}/.." && pwd)"
cd "${repository_directory}/Source/Frameworks/gyroflow"
cargo_command="${CARGO:-${HOME}/.cargo/bin/cargo}"
for option in "$@"; do
    case "$option" in
        --clean) "$cargo_command" clean ;;
        --update) "$cargo_command" update ;;
        *) echo "Unknown build option: $option" >&2; exit 2 ;;
    esac
done
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
architectures="${GYROFLOW_ARCHS:-${ARCHS:-arm64 x86_64}}"
profile="${GYROFLOW_RUST_PROFILE:-release}"
profile_directory="$profile"
if [[ "$profile" == "dev" ]]; then profile_directory="debug"; fi
target_directory="${CARGO_TARGET_DIR:-$PWD/target}"
mkdir -p "$target_directory" binary
target_directory="$(cd "$target_directory" && pwd)"
binaries=()
for architecture in $architectures; do
    case "$architecture" in
        arm64) target="aarch64-apple-darwin" ;;
        x86_64) target="x86_64-apple-darwin" ;;
        *) echo "Unsupported architecture: $architecture" >&2; exit 2 ;;
    esac
    "$cargo_command" build --locked --profile "$profile" --target "$target" --target-dir "$target_directory"
    binaries+=("$target_directory/$target/$profile_directory/libgyroflow_toolbox.dylib")
done
temporary_library="$PWD/binary/libgyroflow_toolbox.$$.dylib"
trap 'rm -f "$temporary_library"' EXIT
xcrun lipo -create "${binaries[@]}" -output "$temporary_library"
xcrun install_name_tool -id "@rpath/libgyroflow_toolbox.dylib" "$temporary_library"
codesign --force --sign - "$temporary_library"
mv "$temporary_library" binary/libgyroflow_toolbox.dylib
