#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/readme-tools docs/assets
swiftc -swift-version 5 -parse-as-library -D README_ASSETS \
  Sources/Inkey/*.swift scripts/render-readme.swift \
  -o build/readme-tools/render-readme
build/readme-tools/render-readme
