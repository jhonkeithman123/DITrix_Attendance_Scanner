#!/usr/bin/env bash
set -euo pipefail

# Edit this to your desired basename
APP_BASENAME="DITrix_Attendance_Scanner"

# Build split apks first:
# flutter build apk --split-per-abi
# The script assumes you ran the command above and the output is in build/app/outputs/apk/release

OUT_DIR="build/app/outputs/apk/release"
if [ ! -d "$OUT_DIR" ]; then
  echo "Output dir not found: $OUT_DIR"
  echo "Run: flutter build apk --split-per-abi"
  exit 1
fi

shopt -s nullglob
for f in "$OUT_DIR"/app-*-release.apk; do
  fname=$(basename "$f")
  # example name: app-arm64-v8a-release.apk
  # extract abi token between "app-" and "-release.apk"
  abi=${fname#app-}
  abi=${abi%-release.apk}
  newname="${APP_BASENAME}-${abi}.apk"
  echo "Renaming $fname -> $newname"
  mv -f "$f" "$OUT_DIR/$newname"
done

# Optional: rename universal APK if present
if [ -f "$OUT_DIR/app-release.apk" ]; then
  echo "Renaming app-release.apk -> ${APP_BASENAME}.apk"
  mv -f "$OUT_DIR/app-release.apk" "$OUT_DIR/${APP_BASENAME}.apk"
fi

echo "Done. Files in $OUT_DIR:"
ls -1 "$OUT_DIR"