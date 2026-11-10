#!/bin/sh
# Build and package the public preview. This script does not upload anything.
set -eu
cd "$(dirname "$0")/.."

release_dir="$PWD/build/releases"
app="$PWD/build/ReleaseDerivedData/Build/Products/Release/Guides.app"
mkdir -p "$release_dir"

xcodebuild -project Guides.xcodeproj -scheme Guides -configuration Release \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  -derivedDataPath build/ReleaseDerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages build

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="Guides-$version-macOS-universal.zip"
checksums="Guides-$version-SHA256SUMS.txt"
architectures=$(lipo -archs "$app/Contents/MacOS/Guides")
case " $architectures " in *' arm64 '*) ;; *) echo 'Missing arm64 slice' >&2; exit 1 ;; esac
case " $architectures " in *' x86_64 '*) ;; *) echo 'Missing x86_64 slice' >&2; exit 1 ;; esac
codesign --verify --deep --strict "$app"
test -s "$app/Contents/Resources/ThirdPartyNotices.txt"
test "$(/usr/libexec/PlistBuddy -c 'Print :GuidesCommandProtocol' "$app/Contents/Info.plist")" = 1
test "$(/usr/libexec/PlistBuddy -c 'Print :GuidesSingleInstance' "$app/Contents/Info.plist")" = true

# Validate an extracted copy as well as the build product before publishing.
package_dir=$(mktemp -d "$release_dir/.package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT HUP INT TERM
distribution="$package_dir/distribution"
mkdir -p "$distribution/skills"
ditto "$app" "$distribution/Guides.app"
cp skills/guides/scripts/guides "$distribution/guides"
ditto skills/guides "$distribution/skills/guides"
cp "docs/releases/$version-install.txt" "$distribution/INSTALL.txt"
ditto -c -k --sequesterRsrc "$distribution" "$package_dir/$archive"
ditto -x -k "$package_dir/$archive" "$package_dir/extracted"
codesign --verify --deep --strict "$package_dir/extracted/Guides.app"
cmp "$app/Contents/MacOS/Guides" "$package_dir/extracted/Guides.app/Contents/MacOS/Guides"
test -x "$package_dir/extracted/guides"
cmp skills/guides/scripts/guides "$package_dir/extracted/guides"
cmp skills/guides/SKILL.md "$package_dir/extracted/skills/guides/SKILL.md"
test -s "$package_dir/extracted/INSTALL.txt"
"$package_dir/extracted/guides" --help > /dev/null
mv "$package_dir/$archive" "$release_dir/$archive"
cd "$release_dir"
shasum -a 256 "$archive" > "$checksums"
printf '\nPackaged %s\nChecksum: %s\nAd hoc signed preview; not Developer ID signed or notarized.\n' \
  "$release_dir/$archive" "$release_dir/$checksums"
