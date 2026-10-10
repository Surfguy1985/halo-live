#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT"

echo "== HALO PREPARE LATEST XCODE =="
echo "Generating Xcode from the explicitly checked-out source without changing branches or files."
LOCAL="$(git rev-parse HEAD)"
echo "Source commit: $LOCAL"

cd "$SCRIPT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen is required. Install it with: brew install xcodegen"
  exit 1
fi

for required in   "HaloField/Features/Camera/CameraProofView.swift"   "HaloField/Features/Map/ManagerLiveView.swift"   "HaloField/Models/HaloMapGeofence.swift"   "HaloField/Design/HaloPremiumMotion.swift"   "HaloField/App/HaloBuildStamp.swift"; do
  [ -f "$required" ] || { echo "ERROR: Missing $required"; exit 1; }
done

BUILD_STAMP="$(sed -nE 's/.*revision = "([^"]+)".*/\1/p' HaloField/App/HaloBuildStamp.swift)"
[ -n "$BUILD_STAMP" ] || { echo "ERROR: native build stamp is missing"; exit 1; }

echo "Closing Xcode so it cannot hold a stale generated project..."
osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true
sleep 2

echo "Removing stale generated project and DerivedData..."
rm -rf HaloField.xcodeproj .derived-data
find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name 'HaloField-*' -prune -exec rm -rf {} + 2>/dev/null || true

echo "Generating current project..."
xcodegen generate

echo "Verifying project and scheme..."
test -f HaloField.xcodeproj/project.pbxproj
xcodebuild -project HaloField.xcodeproj -list | sed -n '/Schemes:/,$p'

echo "Verifying XcodeGen did not mutate tracked native metadata..."
git diff --exit-code -- HaloField/Info.plist HaloField/HaloField.entitlements HaloFieldWidgets/Info.plist >/dev/null || {
  echo "ERROR: XcodeGen changed a tracked plist/entitlements file. Refusing to open a dirty native project."
  git diff -- HaloField/Info.plist HaloField/HaloField.entitlements HaloFieldWidgets/Info.plist
  exit 1
}

grep -q '\$(APS_ENVIRONMENT)' HaloField/HaloField.entitlements || {
  echo "ERROR: APNs entitlement is not wired to APS_ENVIRONMENT."
  exit 1
}

grep -q 'CODE_SIGN_STYLE: Automatic' project.yml || {
  echo "ERROR: Native target is not configured for automatic signing."
  exit 1
}

echo "Opening exact native HALO project..."
open -a Xcode "$SCRIPT_DIR/HaloField.xcodeproj"

echo
echo "SUCCESS"
echo "Commit: $LOCAL"
echo "Build stamp: $BUILD_STAMP"
echo "Project: $SCRIPT_DIR/HaloField.xcodeproj"
echo "Scheme: HaloField"
echo "Bundle: com.archangel.halofield"
echo "In Xcode choose your physical iPhone as the run destination, then press Cmd-R."
