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
ENTITLEMENTS="ChirpApp.entitlements"

echo "▶ Packaging .app..."
rm -rf "$APP"
mkdir -p "$MACOS"

cp "$BINARY" "$MACOS/Chirp"

mkdir -p "$CONTENTS/Resources"
# ChatWebView loads bridge.js via Bundle.main — place it in Contents/Resources/
# so codesign seals it as part of the standard app bundle structure.
cp "$RESOURCE_BUNDLE/bridge.js" "$CONTENTS/Resources/"

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

# Sign with an Apple Development certificate so entitlements (e.g. passkeys) are honored.
# The OS ignores entitlements on unsigned or ad-hoc-signed binaries for protected APIs.
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Apple Development" | head -1 | sed -E 's/.*"(.+)".*/\1/')

if [ -n "$SIGN_IDENTITY" ]; then
  echo "▶ Signing with: $SIGN_IDENTITY"
  # Dev entitlements: passkey support only, no sandbox.
  # The sandbox requires the full .app bundle to be signed, which fails due to the
  # SPM resource bundle structure. Sandbox is a distribution requirement, not dev.
  # Note: com.apple.developer.web-browser.public-key-credential (passkeys) requires
  # a paid Apple Developer Program account. Sign without it for free-account dev builds.
  codesign --force --sign "$SIGN_IDENTITY" \
    "$MACOS/Chirp"
else
  echo "⚠️  No Apple Development certificate found — passkeys will not work."
  echo "   Enroll in the Apple Developer Program and run 'xcodebuild -allowProvisioningUpdates' to install certificates."
fi

echo "▶ Launching..."
open "$APP"
