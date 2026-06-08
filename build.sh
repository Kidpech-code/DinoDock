#!/bin/bash
# Builds DinoDock.app without needing an Xcode project.
# Requires the Xcode command-line tools (you already have Xcode installed).
set -e
cd "$(dirname "$0")"

APP="DinoDock.app"
echo "Building $APP ..."

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O \
  -o "$APP/Contents/MacOS/DinoDock" \
  Sources/DinoDock/*.swift \
  -framework Cocoa \
  -framework Carbon

# Sign the app. Prefer a stable self-signed identity ("DinoDock Local Signing")
# so macOS keeps granted permissions (Accessibility, etc.) across rebuilds; fall
# back to an ad-hoc signature if that certificate isn't installed.
# To create the certificate once, run:  ./make-signing-cert.sh
IDENTITY="DinoDock Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "Signing with: $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
    || codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
else
  echo "Signing ad-hoc (run ./make-signing-cert.sh for permissions that persist across rebuilds)"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "Done."
echo "Run it with:   open $APP"
echo "Quit it from the 🦖 icon in the menu bar."
