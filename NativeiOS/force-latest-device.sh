#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRANCH="ios-swift-native-v1"
STAMP="NATIVE-LIVE-STABILITY-R7"
DERIVED="$SCRIPT_DIR/.device-derived-data"
GLOBAL_DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

echo "== HALO PHYSICAL IPHONE BUILD PREP =="
echo "This preserves local work, syncs the exact native branch, regenerates Xcode, and compiles the device target."

if pgrep -x Xcode >/dev/null 2>&1; then
  osascript -e 'tell application "Xcode" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x Xcode >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -x Xcode >/dev/null 2>&1; then
    echo "ERROR: Xcode is still open. Resolve any save prompt, quit Xcode, and rerun."
    exit 2
  fi
fi

cd "$ROOT"
git fetch --prune origin "$BRANCH"

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  BACKUP="halo-device-local-backup-$(date +%Y%m%d-%H%M%S)"
  echo "Preserving local changes in stash: $BACKUP"
  git stash push -u -m "$BACKUP"
fi

git switch "$BRANCH"
if [ "$(git rev-list --count "origin/$BRANCH..HEAD")" -gt 0 ]; then
  BACKUP_BRANCH="halo-device-commit-backup-$(date +%Y%m%d-%H%M%S)"
  git branch "$BACKUP_BRANCH" HEAD
  echo "Preserved local commits on $BACKUP_BRANCH"
fi
git reset --hard "origin/$BRANCH"

LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$BRANCH")"
[ "$LOCAL" = "$REMOTE" ] || { echo "ERROR: Local HEAD does not equal remote HEAD."; exit 1; }

cd "$SCRIPT_DIR"
command -v xcodegen >/dev/null 2>&1 || { echo "ERROR: Install XcodeGen first: brew install xcodegen"; exit 1; }

grep -q "$STAMP" HaloField/App/HaloBuildStamp.swift || {
  echo "ERROR: Expected build fingerprint $STAMP is missing."
  exit 1
}

echo "Purging stale generated project and HALO build caches..."
rm -rf HaloField.xcodeproj "$DERIVED"
find "$GLOBAL_DERIVED" -maxdepth 1 -type d -name 'HaloField-*' -prune -exec rm -rf {} + 2>/dev/null || true

echo "Generating the native Xcode project..."
xcodegen generate

echo "Compiling the exact iPhone target without signing..."
xcodebuild   -project HaloField.xcodeproj   -scheme HaloField   -configuration Debug   -destination 'generic/platform=iOS'   -derivedDataPath "$DERIVED"   CODE_SIGNING_ALLOWED=NO   clean build

TEAM="$(xcodebuild -project HaloField.xcodeproj -scheme HaloField -configuration Debug -showBuildSettings 2>/dev/null | awk '/DEVELOPMENT_TEAM =/{print $3; exit}')"

echo
echo "SOURCE + DEVICE COMPILE PASSED"
echo "Commit: $LOCAL"
echo "Build fingerprint: $STAMP"
if [ -n "$TEAM" ]; then
  echo "Signing team currently resolved by Xcode: $TEAM"
else
  echo "Signing team is not stored in source. In Xcode choose HaloField target > Signing & Capabilities > Team."
fi

echo
echo "Opening the only project you should run:"
echo "$SCRIPT_DIR/HaloField.xcodeproj"
open -a Xcode "$SCRIPT_DIR/HaloField.xcodeproj"

echo
echo "In Xcode: choose HaloField scheme, choose your connected iPhone, then press Command-R."
echo "If the next failure says Signing/Provisioning/Developer Mode, the Swift device build already passed; fix the Apple signing/device gate shown by Xcode."
