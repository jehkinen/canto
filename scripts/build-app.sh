#!/bin/bash
# Release build of Canto.app (universal: Apple silicon + Intel) into build/, plus a DMG.
#   scripts/build-app.sh            # build/Canto.app and build/Canto-<version>.dmg
#
# Signing: ad-hoc by default, which makes macOS forget Accessibility after every rebuild.
# With a code signing certificate the permission survives rebuilds; a self-signed one named
# "Canto Local Signing" is picked up automatically, or pass SIGN_IDENTITY="…".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d Packages/WhisperBridge/Frameworks/whisper.xcframework ]; then
  scripts/build-whisper.sh
fi

DERIVED="$ROOT/.derived"
OUT="$ROOT/build"
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Canto Local Signing"'; then
  IDENTITY="Canto Local Signing"
fi

xcodebuild -project Canto.xcodeproj -scheme Canto -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  build >"$DERIVED-release.log" 2>&1 || { grep -E "error:" "$DERIVED-release.log" | sort -u; echo "build failed, see $DERIVED-release.log"; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"
ditto "$DERIVED/Build/Products/Release/Canto.app" "$OUT/Canto.app"
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --options runtime --entitlements "$ROOT/Config/Canto.entitlements" \
    --sign "$IDENTITY" "$OUT/Canto.app"
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OUT/Canto.app/Contents/Info.plist")

# A drag-to-Applications disk image.
STAGE="$(mktemp -d)"
ditto "$OUT/Canto.app" "$STAGE/Canto.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Canto $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Canto-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

echo "Canto $VERSION ($(lipo -archs "$OUT/Canto.app/Contents/MacOS/Canto"), signed: ${IDENTITY:-ad-hoc})"
echo "  $OUT/Canto.app"
echo "  $OUT/Canto-$VERSION.dmg"
