#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRANCH="ios-swift-native-v1"
EXPECTED_STAMP="NATIVE-PHOTO-MAP-R4"

cd "$ROOT"

echo "== HALO PREPARE LATEST XCODE =="
echo "Preserving any local edits, syncing exact remote native branch, rebuilding project, and opening Xcode."

git fetch --prune origin "$BRANCH"

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  git stash push -u -m "halo-auto-before-xcode-sync-$STAMP"
  echo "Saved local changes in stash: halo-auto-before-xcode-sync-$STAMP"
fi

git switch "$BRANCH"

if [ "$(git rev-list --count "origin/$BRANCH..HEAD")" -gt 0 ]; then
  BACKUP="halo-backup-before-xcode-sync-$(date +%Y%m%d-%H%M%S)"
  git branch "$BACKUP" HEAD
  echo "Saved local commits on branch: $BACKUP"
fi

git reset --hard "origin/$BRANCH"

LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$BRANCH")"
echo "Local HEAD : $LOCAL"
echo "Remote HEAD: $REMOTE"
[ "$LOCAL" = "$REMOTE" ] || { echo "ERROR: local source does not match remote"; exit 1; }

cd "$SCRIPT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen is required. Install it with: brew install xcodegen"
  exit 1
fi

for required in   "HaloField/Features/Camera/CameraProofView.swift"   "HaloField/Features/Map/ManagerLiveView.swift"   "HaloField/Models/HaloMapGeofence.swift"   "HaloField/Design/HaloPremiumMotion.swift"   "HaloField/App/HaloBuildStamp.swift"; do
  [ -f "$required" ] || { echo "ERROR: Missing $required"; exit 1; }
done

grep -q "$EXPECTED_STAMP" HaloField/App/HaloBuildStamp.swift || {
  echo "ERROR: expected native build stamp $EXPECTED_STAMP not found"
  exit 1
}

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

echo "Opening exact native HALO project..."
open -a Xcode "$SCRIPT_DIR/HaloField.xcodeproj"

echo
echo "SUCCESS"
echo "Commit: $LOCAL"
echo "Build stamp: $EXPECTED_STAMP"
echo "Project: $SCRIPT_DIR/HaloField.xcodeproj"
echo "Scheme: HaloField"
echo "Bundle: com.archangel.halofield"
echo "In Xcode choose your physical iPhone as the run destination, then press Cmd-R."
