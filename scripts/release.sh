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
#   3. A Sparkle EdDSA key (private key in Keychain): run `generate_keys` once;
#      the public key is already in Info.plist as SUPublicEDKey.
#   4. `gh` installed and authenticated (`gh auth login`) to publish the release.
#
# IMPORTANT: bump CURRENT_PROJECT_VERSION (and MARKETING_VERSION) in project.yml
# before each release — Sparkle compares CFBundleVersion, so an un-bumped build
# won't be offered as an update.
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
OWNER_REPO="Yacolate0519-cmd/PortSense"

cd "$(dirname "$0")/.."
DERIVED="$(mktemp -d)"
STAGE="$(mktemp -d)"
DIST="$PWD/dist"
# Space-free filename: GitHub rewrites spaces in release-asset URLs, which would
# break the appcast enclosure link.
DMG="$DIST/PortSense.dmg"
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

# Sparkle ships nested helpers (XPC services, Autoupdate, Updater.app) that each
# need their own hardened-runtime Developer ID signature, signed inside-out
# before the outer app. Skip this and notarization rejects the bundle.
echo "▸ Signing embedded Sparkle helpers…"
FW="$APP/Contents/Frameworks/Sparkle.framework"
FWVER="$(readlink "$FW/Versions/Current")"
for item in \
  "$FW/Versions/$FWVER/XPCServices/Downloader.xpc" \
  "$FW/Versions/$FWVER/XPCServices/Installer.xpc" \
  "$FW/Versions/$FWVER/Autoupdate" \
  "$FW/Versions/$FWVER/Updater.app" \
  "$FW"; do
  [ -e "$item" ] && codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$item"
done

# `xcodebuild build` injects com.apple.security.get-task-allow (a debug
# entitlement) which notarization rejects. Re-sign cleanly with hardened
# runtime and no entitlements to strip it.
echo "▸ Re-signing without get-task-allow (hardened runtime)…"
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"

echo "▸ Verifying app signature…"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow" \
  && { echo "✗ get-task-allow still present"; exit 1; } || echo "  ok: no get-task-allow"

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

# EdDSA-sign the .dmg and build the Sparkle appcast. generate_appcast reads the
# version from inside the .dmg and signs with the private key in the Keychain.
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
TAG="v$VERSION"
GEN_APPCAST="$(find "$DERIVED/SourcePackages/artifacts" -name generate_appcast -type f | head -1)"
ARCHIVES="$(mktemp -d)"
cp "$DMG" "$ARCHIVES/"

echo "▸ Building appcast.xml…"
"$GEN_APPCAST" "$ARCHIVES" \
  --download-url-prefix "https://github.com/$OWNER_REPO/releases/download/$TAG/"
cp "$ARCHIVES/appcast.xml" "$DIST/appcast.xml"

echo "▸ Publishing GitHub release $TAG (dmg + appcast)…"
if gh release view "$TAG" --repo "$OWNER_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" "$ARCHIVES/appcast.xml" --repo "$OWNER_REPO" --clobber
else
  gh release create "$TAG" "$DMG" "$ARCHIVES/appcast.xml" \
    --repo "$OWNER_REPO" --title "$TAG" --generate-notes
fi

echo "✅ Done → released $TAG"
echo "   Gatekeeper check:"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true
