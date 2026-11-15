#!/bin/bash
set -euo pipefail

[[ "$(uname -m)" == arm64 ]]
swift build -c release --product MacTerm
swift build -c release --product SSHAskPass
products="$(swift build -c release --show-bin-path)"
app="dist/MacTerm.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp "$products/MacTerm" "$app/Contents/MacOS/"
cp "$products/SSHAskPass" "$app/Contents/Helpers/"
cp packaging/Info.plist "$app/Contents/"
shopt -s nullglob
for resource in "$products"/*.bundle; do
    ditto "$resource" "$app/Contents/Resources/$(basename "$resource")"
done
if [[ -n "${MACTERM_VERSION:-}" ]]; then
    [[ "$MACTERM_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MACTERM_VERSION" "$app/Contents/Info.plist"
fi
[[ "$(lipo -archs "$app/Contents/MacOS/MacTerm")" == arm64 ]]
identity="${MACTERM_SIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$app/Contents/Helpers/SSHAskPass"
    codesign --force --sign - "$app"
else
    codesign --force --timestamp --options runtime --sign "$identity" "$app/Contents/Helpers/SSHAskPass"
    codesign --force --timestamp --options runtime --sign "$identity" "$app"
fi
codesign --verify --strict "$app/Contents/Helpers/SSHAskPass"
codesign --verify --deep --strict "$app"
mkdir -p dist/image
ditto "$app" dist/image/MacTerm.app
ln -sfn /Applications dist/image/Applications
hdiutil create -ov -volname MacTerm -srcfolder dist/image -format UDZO dist/MacTerm.dmg
ditto -c -k --keepParent "$app" dist/MacTerm.app.zip
hdiutil verify dist/MacTerm.dmg
