#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcodebuild -project Guides.xcodeproj -scheme Guides -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages build
