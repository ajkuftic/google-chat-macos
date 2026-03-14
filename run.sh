#!/bin/bash
# Build and launch Chirp as a proper .app bundle for local development.
set -e

echo "▶ Building..."
swift build 2>&1

BINARY=".build/debug/Chirp"
RESOURCE_BUNDLE=".build/debug/Chirp_Chirp.bundle"
APP=".build/Chirp.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

echo "▶ Packaging .app..."
rm -rf "$APP"
mkdir -p "$MACOS"

cp "$BINARY" "$MACOS/Chirp"

# Bundle.module resolves the resource bundle relative to the executable.
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -r "$RESOURCE_BUNDLE" "$MACOS/"
fi

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>    <string>Chirp</string>
  <key>CFBundleIdentifier</key>   <string>com.ajkuftic.Chirp</string>
  <key>CFBundleName</key>         <string>Chirp</string>
  <key>CFBundleVersion</key>      <string>1</string>
  <key>CFBundleShortVersionString</key> <string>0.1.0</string>
  <key>CFBundlePackageType</key>  <string>APPL</string>
  <key>LSMinimumSystemVersion</key> <string>14.0</string>
  <key>NSPrincipalClass</key>     <string>NSApplication</string>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "▶ Launching..."
open "$APP"
