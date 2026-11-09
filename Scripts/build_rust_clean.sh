#!/bin/bash
set -euo pipefail
exec "$(dirname -- "$0")/build_rust.sh" --clean "$@"
