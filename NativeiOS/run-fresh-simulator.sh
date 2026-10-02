#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRANCH="ios-swift-native-v1"
BUNDLE_ID="com.archangel.halofield"
LEGACY_BUNDLE_ID="com.archangel.halolive"

# First pass: make the local checkout exactly match the remote native branch.
# Any local work is preserved in an automatic stash before the reset.
if [ "${HALO_REMOTE_SYNCED:-0}" != "1" ]; then
  cd "$ROOT"
  echo "== HALO remote source sync =="
  echo "Repo: $ROOT"

  git fetch --prune origin "$BRANCH"

  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    echo "Local changes detected. Preserving them in stash: halo-auto-before-native-sync-$STAMP"
    git stash push -u -m "halo-auto-before-native-sync-$STAMP"
  fi

  git switch "$BRANCH"
  if [ "$(git rev-list --count "origin/$BRANCH..HEAD")" -gt 0 ]; then
    BACKUP="halo-backup-before-sync-$(date +%Y%m%d-%H%M%S)"
    git branch "$BACKUP" HEAD
    echo "Local commits preserved on $BACKUP"
  fi
  git reset --hard "origin/$BRANCH"

  LOCAL="$(git rev-parse HEAD)"
  REMOTE="$(git rev-parse "origin/$BRANCH")"
  echo "Local HEAD : $LOCAL"
  echo "Remote HEAD: $REMOTE"

  if [ "$LOCAL" != "$REMOTE" ]; then
    echo "ERROR: Local source still does not match origin/$BRANCH"
    exit 1
  fi

  echo "Remote source verified. Re-entering the synced launcher..."
  exec env HALO_REMOTE_SYNCED=1 bash "$SCRIPT_DIR/run-fresh-simulator.sh"
fi

cd "$SCRIPT_DIR"
DERIVED="$PWD/.derived-data"
GLOBAL_DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

echo
echo "== HALO native clean simulator launch =="
echo "Branch: $(git branch --show-current)"
echo "Commit: $(git rev-parse HEAD)"
echo "Remote: $(git rev-parse origin/$BRANCH)"

if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$BRANCH)" ]; then
  echo "ERROR: Refusing to build because local HEAD is not the remote native HEAD."
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

echo "Purging generated Xcode project and build caches..."
rm -rf HaloField.xcodeproj "$DERIVED"
find "$GLOBAL_DERIVED" -maxdepth 1 -type d -name 'HaloField-*' -prune -exec rm -rf {} + 2>/dev/null || true

echo "Generating HaloField.xcodeproj from the synced project.yml..."
xcodegen generate

echo "Verifying runnable HaloField scheme..."
xcodebuild -project HaloField.xcodeproj -list | sed -n '/Schemes:/,$p'

UDID="$(xcrun simctl list devices booted -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for rows in d.values() for x in rows if x.get("state")=="Booted" and "iPhone" in x.get("name","")), ""))')"

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

echo "Stopping HALO before reinstall (preserving offline photos and queued work)..."
xcrun simctl terminate "$UDID" "$LEGACY_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Building exact HaloField scheme from verified remote source..."
xcodebuild \
  -project HaloField.xcodeproj \
  -scheme HaloField \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED" \
  clean build

APP="$DERIVED/Build/Products/Debug-iphonesimulator/HaloField.app"
if [ ! -d "$APP" ]; then
  echo "ERROR: Expected app not found at $APP"
  exit 1
fi

echo "Installing fresh binary: $APP"
xcrun simctl install "$UDID" "$APP"

INSTALLED_BUNDLE="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" app 2>/dev/null || true)"
echo "Installed app container: $INSTALLED_BUNDLE"

echo "Launching $BUNDLE_ID..."
xcrun simctl launch "$UDID" "$BUNDLE_ID"

echo
echo "SUCCESS: REMOTE-SYNCED HALO FIELD NATIVE build launched."
echo "Native source commit: $(git rev-parse HEAD)"
echo "Bundle launched: $BUNDLE_ID"
echo "Open Me and confirm the DEBUG build stamp starts with PREMIUM-UI."
echo "Expected nav: Today · Jobs · HALO · Live(if authorized) · Me"
