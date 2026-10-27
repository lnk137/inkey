#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/readme-tools docs/assets
logo_dir="$(mktemp -d "$PWD/build/readme-tools/logo.XXXXXX")"
trap 'rm -rf "$logo_dir"' EXIT
swift scripts/make-icon.swift "$logo_dir"
cp "$logo_dir/Inkey.iconset/icon_256x256@2x.png" docs/assets/inkey-logo.png
swiftc -swift-version 5 -parse-as-library -D README_ASSETS \
  Sources/Inkey/*.swift scripts/render-readme.swift scripts/render-readme-flows.swift \
  -o build/readme-tools/render-readme
build/readme-tools/render-readme
