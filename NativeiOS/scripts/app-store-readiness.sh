#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "APP STORE READINESS: FAIL — $*" >&2; exit 1; }
pass() { echo "✓ $*"; }

PROJECT="project.yml"
INFO="HaloField/Info.plist"
PRIVACY="HaloField/PrivacyInfo.xcprivacy"
ENTITLEMENTS="HaloField/HaloField.entitlements"
ICON="HaloField/Assets.xcassets/AppIcon.appiconset/Contents.json"

grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.archangel.halofield' "$PROJECT" || fail "production bundle identifier missing"
grep -q 'CFBundleShortVersionString: "1.0.0"' "$PROJECT" || fail "marketing version is not 1.0.0"
grep -q 'CFBundleVersion: "1"' "$PROJECT" || fail "build number is not 1"
grep -q 'APNS_ENVIRONMENT: production' "$PROJECT" || fail "Release APNs environment is not production"
grep -q 'remote-notification' "$PROJECT" || fail "remote notification background mode missing"
grep -q 'location' "$PROJECT" || fail "location background mode missing"
grep -q 'NSCameraUsageDescription' "$PROJECT" || fail "camera purpose string missing"
grep -q 'NSLocationWhenInUseUsageDescription' "$PROJECT" || fail "when-in-use location purpose string missing"
grep -q 'NSLocationAlwaysAndWhenInUseUsageDescription' "$PROJECT" || fail "background location purpose string missing"
grep -q 'NSPhotoLibraryUsageDescription' "$PROJECT" || fail "photo library purpose string missing"
grep -q 'NSSupportsLiveActivities: YES' "$PROJECT" || fail "Live Activities declaration missing"

plutil -lint "$INFO" >/dev/null || fail "Info.plist invalid"
plutil -lint "$PRIVACY" >/dev/null || fail "PrivacyInfo.xcprivacy invalid"
plutil -lint "$ENTITLEMENTS" >/dev/null || fail "entitlements invalid"
grep -q 'NSPrivacyTracking' "$PRIVACY" || fail "privacy tracking declaration missing"
grep -q 'NSPrivacyCollectedDataTypePreciseLocation' "$PRIVACY" || fail "precise location privacy disclosure missing"
grep -q 'NSPrivacyCollectedDataTypePhotosorVideos' "$PRIVACY" || fail "photo/video privacy disclosure missing"
grep -q 'NSPrivacyCollectedDataTypeUserID' "$PRIVACY" || fail "user ID privacy disclosure missing"
grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' "$PRIVACY" || fail "UserDefaults required-reason API declaration missing"
grep -q 'CA92.1' "$PRIVACY" || fail "UserDefaults approved reason missing"

python3 - "$ICON" <<'PY'
import json,sys
p=sys.argv[1]
data=json.load(open(p))
images=data.get("images",[])
if not images:
    raise SystemExit("App icon catalog has no image entries")
missing=[x for x in images if x.get("idiom")=="universal" and x.get("platform")=="ios" and not x.get("filename")]
if missing:
    raise SystemExit("Universal iOS app icon entry is missing a filename")
PY

pass "bundle/version/release configuration"
pass "privacy manifest and required-reason declaration"
pass "camera/location/photo permission purpose strings"
pass "production push + Live Activity declarations"
pass "App Store icon catalog"
echo "APP STORE READINESS: STATIC GATES PASSED"
