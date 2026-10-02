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
grep -Eq 'CFBundleVersion: "[1-9][0-9]*"' "$PROJECT" || fail "build number must be a positive integer"
grep -q 'APS_ENVIRONMENT: production' "$PROJECT" || fail "Release APNs environment is not production"
grep -q 'remote-notification' "$PROJECT" || fail "remote notification background mode missing"
grep -q 'location' "$PROJECT" || fail "location background mode missing"
grep -q 'NSCameraUsageDescription' "$PROJECT" || fail "camera purpose string missing"
grep -q 'NSLocationWhenInUseUsageDescription' "$PROJECT" || fail "when-in-use location purpose string missing"
grep -q 'NSLocationAlwaysAndWhenInUseUsageDescription' "$PROJECT" || fail "background location purpose string missing"
grep -q 'NSPhotoLibraryUsageDescription' "$PROJECT" || fail "photo library purpose string missing"
grep -q 'NSSupportsLiveActivities: YES' "$PROJECT" || fail "Live Activities declaration missing"

python3 - "$INFO" "$PRIVACY" "$ENTITLEMENTS" <<'PYPLIST'
import plistlib, sys
for path in sys.argv[1:]:
    with open(path, 'rb') as source:
        plistlib.load(source)
PYPLIST
grep -q 'NSPrivacyTracking' "$PRIVACY" || fail "privacy tracking declaration missing"
grep -q 'NSPrivacyCollectedDataTypePreciseLocation' "$PRIVACY" || fail "precise location privacy disclosure missing"
grep -q 'NSPrivacyCollectedDataTypePhotosorVideos' "$PRIVACY" || fail "photo/video privacy disclosure missing"
grep -q 'NSPrivacyCollectedDataTypeUserID' "$PRIVACY" || fail "user ID privacy disclosure missing"
grep -q 'NSPrivacyAccessedAPICategoryUserDefaults' "$PRIVACY" || fail "UserDefaults required-reason API declaration missing"
grep -q 'CA92.1' "$PRIVACY" || fail "UserDefaults approved reason missing"

python3 - "$ICON" <<'PY'
import json, sys, pathlib, struct
p=pathlib.Path(sys.argv[1])
images=json.loads(p.read_text()).get("images", [])
icons=[x for x in images if x.get("idiom")=="universal" and x.get("platform")=="ios"]
if not icons:
    raise SystemExit("Universal iOS app icon is missing")
for entry in icons:
    path=p.parent / entry.get("filename", "")
    if not path.is_file() or path.suffix.lower() != '.png':
        raise SystemExit("App Store icon must reference an existing PNG")
    data=path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise SystemExit("App Store icon is not a PNG")
    width,height,depth,color=struct.unpack('>IIBB',data[16:26])
    if (width,height)!=(1024,1024) or depth != 8 or color != 2:
        raise SystemExit("App Store icon must be 1024x1024 opaque 8-bit RGB")
    offset=8
    while offset < len(data):
        length=struct.unpack('>I',data[offset:offset+4])[0]
        if data[offset+4:offset+8] == b'tRNS':
            raise SystemExit("App Store icon must not contain transparency")
        offset += length+12

PY

pass "bundle/version/release configuration"
pass "privacy manifest and required-reason declaration"
pass "camera/location/photo permission purpose strings"
pass "production push + Live Activity declarations"
pass "App Store icon catalog"
echo "APP STORE READINESS: STATIC GATES PASSED"
