#!/bin/bash
set -euo pipefail

[[ "$(uname -m)" == arm64 ]]
swift build -c release --product MacTerm
products="$(swift build -c release --show-bin-path)"
app="dist/MacTerm.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/MacTerm" "$app/Contents/MacOS/"
cp packaging/Info.plist "$app/Contents/"
shopt -s nullglob
for resource in "$products"/*.bundle; do
    ditto "$resource" "$app/$(basename "$resource")"
done
if [[ -n "${MACTERM_VERSION:-}" ]]; then
    [[ "$MACTERM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MACTERM_VERSION" "$app/Contents/Info.plist"
fi
[[ "$(lipo -archs "$app/Contents/MacOS/MacTerm")" == arm64 ]]
identity="${MACTERM_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app"
else
    codesign --force --timestamp --options runtime --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
hdiutil create -overwrite -volname MacTerm -srcfolder "$app" -format UDZO dist/MacTerm.dmg
hdiutil verify dist/MacTerm.dmg
