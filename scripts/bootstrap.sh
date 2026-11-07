#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK was not found in PATH.' >&2
  exit 1
fi

flutter create --project-name denuczi_tv --platforms=linux,windows .
python3 scripts/apply_branding.py
flutter pub get

echo 'Project platform runners generated. Run flutter analyze and flutter test next.'
