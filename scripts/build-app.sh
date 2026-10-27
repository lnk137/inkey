#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_dir="$PWD/build/Inkey.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Inkey" "$app_dir/Contents/MacOS/Inkey"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
for localization in Sources/Inkey/Resources/*.lproj; do
  ditto "$localization" "$app_dir/Contents/Resources/$(basename "$localization")"
done
swift scripts/make-icon.swift "$PWD/build"
iconutil -c icns build/Inkey.iconset -o "$app_dir/Contents/Resources/Inkey.icns"
rm -rf build/Inkey.iconset
codesign --force --sign - "$app_dir"
printf 'Built %s\n' "$app_dir"
