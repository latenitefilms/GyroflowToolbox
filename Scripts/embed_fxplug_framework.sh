#!/bin/bash
# Embed from the same SDK installation used to compile and link the renderer.
set -euo pipefail
framework="${1:?Specify FxPlug or PluginManager}"
case "$framework" in FxPlug|PluginManager) ;; *) exit 2 ;; esac
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_framework="${FXPLUG_DEVELOPER_DIR:-/Library/Developer}/Frameworks/$framework.framework"
destination_framework="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/$framework.framework"
python3 "$script_directory/check_deployment.py" --minimum "$MACOSX_DEPLOYMENT_TARGET" "$source_framework/$framework"
mkdir -p "$destination_framework"
rsync --archive --links --whole-file --no-owner --no-group --checksum --exclude='Headers' \
    "$source_framework/" "$destination_framework/"
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
    codesign --force --timestamp --options runtime \
        --sign "${EXPANDED_CODE_SIGN_IDENTITY:-$HARDCODED_DEVELOPER_ID}" "$destination_framework"
fi
