#!/bin/sh
# Builds a Release copy of Port Watcher and installs it to /Applications so
# Spotlight, Launchpad and Login Items can find it.
set -e
cd "$(dirname "$0")/.."
xcodebuild -project PortWatcher/PortWatcher.xcodeproj -scheme PortWatcher \
  -configuration Release -derivedDataPath .build/xcode build 2>&1 | grep -E 'error:|BUILD'
APP=.build/xcode/Build/Products/Release/PortWatcher.app
pkill -f "PortWatcher.app/Contents/MacOS/PortWatcher" 2>/dev/null || true
rm -rf /Applications/PortWatcher.app
cp -R "$APP" /Applications/PortWatcher.app
echo "Installed /Applications/PortWatcher.app"
open /Applications/PortWatcher.app
