#!/usr/bin/env bash
# Package an existing Flutter release bundle without rebuilding or installing it.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/package_deb.py" "$@"
