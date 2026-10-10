#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_ID="com.archangel.halofield"
DERIVED="$SCRIPT_DIR/.iphone-install-derived-data"

echo "== HALO CLEAN IPHONE INSTALL =="
echo "Build the explicitly checked-out commit -> regenerate Xcode -> sign -> clean install -> launch"

if [ ! -d "/Applications/Xcode.app" ]; then
  echo "ERROR: Xcode.app is not installed in /Applications."
  exit 2
fi

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

if pgrep -x Xcode >/dev/null 2>&1; then
  osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true
  sleep 2
fi

cd "$ROOT"
LOCAL="$(git rev-parse HEAD)"
echo "Source commit: $LOCAL"
echo "This script never fetches, switches, stashes, or resets Git."

cd "$SCRIPT_DIR"
command -v xcodegen >/dev/null 2>&1 || {
  echo "ERROR: XcodeGen is required. Install it with: brew install xcodegen"
  exit 2
}

echo "Detecting connected PHYSICAL iPhone..."
DEVICE_ID="${HALO_DEVICE_ID:-}"

# xctrace lists both simulators and real devices. Never pick from that mixed list.
# CoreDevice/devicectl only exposes connected physical Apple devices here.
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null | awk '
    /iPhone/ && ($0 ~ /connected|available|paired/) {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^0000[0-9A-Fa-f-]+$/) { print $i; exit }
      }
    }'
  )"
fi

if [ -z "$DEVICE_ID" ]; then
  echo "ERROR: No connected physical iPhone was detected."
  echo "Unlock the iPhone, connect USB, tap Trust, enable Developer Mode, then rerun."
  echo
  echo "Connected physical devices reported by CoreDevice:"
  xcrun devicectl list devices 2>/dev/null || true
  echo
  echo "You can also run: HALO_DEVICE_ID=<physical-iphone-UDID> bash install-latest-device.sh"
  exit 3
fi

# Hard guard: reject simulator UUIDs or any identifier CoreDevice cannot resolve.
if ! xcrun devicectl device info details --device "$DEVICE_ID" >/dev/null 2>&1; then
  echo "ERROR: $DEVICE_ID is not a connected physical CoreDevice."
  echo "Refusing to build a Simulator app for an iPhone install."
  exit 3
fi

echo "Physical iPhone: $DEVICE_ID"

TEAM="${HALO_DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ]; then
  TEAM="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/.*Apple Development:.*\(([A-Z0-9]{10})\).*/\1/p' | head -1)"
fi

if [ -z "$TEAM" ]; then
  echo "ERROR: No Apple Development signing team/certificate was found."
  echo "Open Xcode > Settings > Accounts, sign in with your Apple ID, then create/download an Apple Development certificate."
  echo "Or rerun with: HALO_DEVELOPMENT_TEAM=<TEAM_ID> bash install-latest-device.sh"
  exit 4
fi

echo "Signing team: $TEAM"
echo "Source commit: $LOCAL"

echo "Purging stale HALO projects and DerivedData..."
rm -rf HaloField.xcodeproj "$DERIVED"
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name 'HaloField-*' -prune -exec rm -rf {} + 2>/dev/null || true

echo "Regenerating Xcode project..."
xcodegen generate

echo "Building and signing for the connected iPhone..."
xcodebuild \
  -project HaloField.xcodeproj \
  -scheme HaloField \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  clean build

APP="$DERIVED/Build/Products/Debug-iphoneos/HaloField.app"
SIM_APP="$DERIVED/Build/Products/Debug-iphonesimulator/HaloField.app"

if [ -d "$SIM_APP" ] && [ ! -d "$APP" ]; then
  echo "ERROR: Xcode produced a Simulator build instead of a physical-iPhone build."
  echo "Destination was: platform=iOS,id=$DEVICE_ID"
  echo "Do not install this product. Reconnect/unlock the physical iPhone and rerun."
  exit 5
fi

[ -d "$APP" ] || {
  echo "ERROR: Signed physical-iPhone HALO app was not produced at $APP"
  echo "Expected platform: iphoneos"
  exit 5
}

echo "Removing stale HALO install if present..."
xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Installing signed HALO app..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "Launching HALO..."
if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
  echo
  echo "INSTALL SUCCEEDED, BUT iOS BLOCKED LAUNCH."
  echo "On iPhone verify:"
  echo "  1. Settings > Privacy & Security > Developer Mode = ON"
  echo "  2. iPhone is unlocked and still connected/trusted"
  echo "  3. If Settings shows VPN & Device Management / Developer App, trust your Apple ID"
  echo "Then rerun this script. The app itself is already signed and installed."
  exit 6
fi

echo
echo "HALO INSTALLED + LAUNCHED"
echo "Commit: $LOCAL"
echo "Bundle: $BUNDLE_ID"
echo "Device: $DEVICE_ID"
