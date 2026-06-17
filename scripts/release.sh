#!/usr/bin/env bash
#
# Build, Developer ID-sign, notarize, and package Port Sense into a .dmg.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login Keychain.
#   2. A notarization credential profile stored in the Keychain:
#        xcrun notarytool store-credentials "PortSense-notary" \
#          --apple-id "<your-apple-id-email>" \
#          --team-id  "42PG64AMFA" \
#          --password "<app-specific-password>"   # from appleid.apple.com
#
# No secrets live in this file — signing reads the cert from your Keychain and
# notarization references the Keychain profile by name only.
#
# Usage:  ./scripts/release.sh

set -euo pipefail

SCHEME="PortSense"
APP_NAME="Port Sense"
TEAM_ID="42PG64AMFA"
SIGN_ID="Developer ID Application: Jun-Bo Huang (42PG64AMFA)"
NOTARY_PROFILE="PortSense-notary"

cd "$(dirname "$0")/.."
DERIVED="$(mktemp -d)"
STAGE="$(mktemp -d)"
DIST="$PWD/dist"
DMG="$DIST/$APP_NAME.dmg"
mkdir -p "$DIST"

echo "▸ Building Release (Developer ID signed, hardened runtime)…"
xcodebuild -project PortSense.xcodeproj -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"

echo "▸ Verifying app signature…"
codesign --verify --strict --verbose=2 "$APP"

echo "▸ Packaging .dmg…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

echo "▸ Signing the .dmg…"
codesign --sign "$SIGN_ID" --timestamp "$DMG"

echo "▸ Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling the notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ Done → $DMG"
echo "   Gatekeeper check:"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
