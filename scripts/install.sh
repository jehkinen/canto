#!/bin/bash
# Installs build/Canto.app into /Applications (or ~/Applications when /Applications is not
# writable) and opens it.
# A running Canto is asked to quit first (it quits cleanly on SIGTERM and gives Caps Lock back),
# so the app you use is never replaced while it runs. Rebuilds only touch build/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Canto.app"
if [ -w /Applications ]; then
  DESTINATION="/Applications/Canto.app"
else
  DESTINATION="$HOME/Applications/Canto.app"
fi

[ -d "$SOURCE" ] || "$ROOT/scripts/build-app.sh"

if pgrep -x Canto >/dev/null; then
  pkill -x Canto
  for _ in $(seq 1 50); do pgrep -x Canto >/dev/null || break; sleep 0.1; done
fi

mkdir -p "$(dirname "$DESTINATION")"
rm -rf "$DESTINATION"
# Only one copy, so Finder, Spotlight and System Settings never show a stale one.
[ "$DESTINATION" = "/Applications/Canto.app" ] && rm -rf "$HOME/Applications/Canto.app"
ditto "$SOURCE" "$DESTINATION"
open "$DESTINATION"
echo "Canto installed to $DESTINATION"
