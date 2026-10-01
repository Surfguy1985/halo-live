# HALO Field — Native iOS

HALO Field is the production native SwiftUI field-operations client for HALO Back Office.

## Release
- Bundle ID: `com.archangel.halofield`
- Version: `1.0.0`
- iOS: 17+
- iPhone portrait
- Scheme: `HaloField`
- Backend: HALO Back Office / Base44
- Auth: revocable native activation credential
- Realtime: authenticated WebSocket with resilient fallback sync

## Production capabilities
- Strict crew vs office authorization
- Today briefing and assigned jobs
- Photo + GPS arrival verification
- Before/after/flagged work evidence
- Checklists, workflow transitions, rework and handoff
- Offline mutation queue with replay and Sync Issues
- HALO messaging with private signed attachments and read receipts
- Push/deep links and Live Activities
- Manager Live Operations map for authorized office credentials
- Production health telemetry and scoped realtime invalidation

## Generate the project
```bash
brew install xcodegen
cd NativeiOS
xcodegen generate
open HaloField.xcodeproj
```

Run the `HaloField` scheme, not `HaloFieldWidgets`.

## Deterministic simulator launch
```bash
cd NativeiOS
bash run-fresh-simulator.sh
```

The launcher removes both the legacy Capacitor bundle and the native bundle before installing a clean native build.

## App Store readiness
```bash
cd NativeiOS
bash scripts/app-store-readiness.sh
```

See `APP_STORE_SUBMISSION.md` for App Review notes, privacy declarations, screenshots, and release-owner gates.

Native CI regenerates the project, validates App Store static gates, runs the test target, and creates an unsigned generic-iOS Release archive.
