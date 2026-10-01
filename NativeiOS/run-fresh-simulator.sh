#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

BUNDLE_ID="com.archangel.halofield"
DERIVED="$PWD/.derived-data"

echo "== HALO native clean simulator launch =="
echo "Repo: $(git rev-parse --show-toplevel)"
echo "Branch: $(git branch --show-current)"
echo "Commit: $(git rev-parse --short HEAD)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

echo "Generating HaloField.xcodeproj from project.yml..."
rm -rf HaloField.xcodeproj "$DERIVED"
xcodegen generate

echo "Verifying runnable HaloField scheme..."
xcodebuild -project HaloField.xcodeproj -list | sed -n '/Schemes:/,$p'

UDID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for rows in d.values() for x in rows if x.get("state")=="Booted"), ""))')"

if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for rows in d.values() for x in rows if "iPhone" in x.get("name","") and x.get("isAvailable",False)), ""))')"
  if [ -z "$UDID" ]; then
    echo "ERROR: No available iPhone simulator found."
    exit 1
  fi
  echo "Booting simulator $UDID..."
  xcrun simctl boot "$UDID" || true
  open -a Simulator
  xcrun simctl bootstatus "$UDID" -b
fi

echo "Removing any installed HALO app..."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Building exact HaloField scheme from current source..."
xcodebuild   -project HaloField.xcodeproj   -scheme HaloField   -configuration Debug   -sdk iphonesimulator   -destination "platform=iOS Simulator,id=$UDID"   -derivedDataPath "$DERIVED"   clean build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/HaloField.app"
if [ ! -d "$APP" ]; then
  echo "ERROR: Expected app not found at $APP"
  exit 1
fi

echo "Installing fresh binary: $APP"
xcrun simctl install "$UDID" "$APP"

echo "Launching $BUNDLE_ID..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo
echo "SUCCESS: Fresh HALO native build launched."
echo "Expected DEBUG fingerprint in app: NATIVE · OCT 1 · FFAB+"
echo "Expected nav: Today · Jobs · HALO · Live(if authorized) · Me"
