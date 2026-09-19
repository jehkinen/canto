#!/bin/bash
# Renders the UI to PNGs in the given language: scripts builds the tool, wraps it in a bundle with
# the app's compiled strings (SwiftUI looks them up in Bundle.main) and runs it.
#   Tools/Snapshots/render.sh <output-dir> [en|ru|he]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?output dir}"
LANGUAGE="${2:-en}"
APP_RESOURCES="${APP_RESOURCES:-$HERE/../../build/Canto.app/Contents/Resources}"

swift build -c release --package-path "$HERE" >/dev/null
BIN="$(swift build -c release --package-path "$HERE" --show-bin-path)/CantoSnapshots"
BUNDLE="$HERE/.build/CantoSnapshots.app"
rm -rf "$BUNDLE" && mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/CantoSnapshots"
cp -R "$APP_RESOURCES"/*.lproj "$BUNDLE/Contents/Resources/" 2>/dev/null || true
cat >"$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.canto.snapshots</string>
<key>CFBundleExecutable</key><string>CantoSnapshots</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string><string>he</string></array>
</dict></plist>
PLIST
case "$LANGUAGE" in ru) LOCALE=ru_RU ;; he) LOCALE=he_IL ;; *) LOCALE=en_US ;; esac
"$BUNDLE/Contents/MacOS/CantoSnapshots" "$OUT" -AppleLanguages "($LANGUAGE)" -AppleLocale "$LOCALE" &
PID=$!
for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; sleep 1; done
if kill -0 $PID 2>/dev/null; then kill $PID; echo "timed out"; exit 1; fi
wait $PID
