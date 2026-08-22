#!/bin/bash
# Builds MeetingScribe.app into ./dist. Run on your Mac from this directory:
#   ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Building (release)…"
swift build -c release

APP=dist/MeetingScribe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MeetingScribe "$APP/Contents/MacOS/MeetingScribe"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo
echo "✅ Built $APP"
echo "   Launch with:  open $APP"
echo "   Tip: add it to System Settings ▸ General ▸ Login Items to run at startup."
