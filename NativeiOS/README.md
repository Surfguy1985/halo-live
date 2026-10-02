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

## Force the complete latest build into Xcode
If Xcode is showing an older HALO UI, use the force-refresh launcher. It closes the in-memory project first, preserves local edits, syncs the exact remote native branch, deletes generated project/build caches, regenerates `HaloField.xcodeproj`, clean-builds, installs the simulator binary, launches HALO, and reopens the correct Xcode project.

```bash
cd NativeiOS
bash force-latest-xcode.sh
```

The expected debug stamp on **Me** is `NATIVE-PHOTO-MAP-R4`. The complete build includes `CameraProofView.swift`, `ManagerLiveView.swift`, `HaloMapGeofence.swift`, map clustering, photo proof, Unit Journey, and premium motion primitives.

## Deterministic simulator launch
```bash
cd NativeiOS
bash run-fresh-simulator.sh
```

The normal launcher preserves local edits in a stash and local commits on a backup branch, syncs the native branch, regenerates the Xcode project, and rebuilds the native app. Reinstallation preserves queued photos, offline work, and activation. Run the `HaloField` scheme, never the legacy Capacitor workspace. If Xcode warns that the project changed externally, choose the version **on disk**.

## App Store readiness
```bash
cd NativeiOS
bash scripts/app-store-readiness.sh
```

See `APP_STORE_SUBMISSION.md` for App Review notes, privacy declarations, screenshots, and release-owner gates.

Native CI regenerates the project, validates App Store static gates, runs the test target, and creates an unsigned generic-iOS Release archive.

## Native Live Operations map
Office credentials receive the live map. Crew credentials retain their assigned daily work.
- Branded crew photo bubbles and searchable roster, including crews with unavailable GPS.
- Standard/satellite maps, property filters, follow-selected-crew, and fit-to-view controls.
- GPS freshness ages locally: live through two minutes, recent through fifteen, then removed from the map.
- Blue arrival-geofence circles come from configured property coordinates and the native check-in radius.
- Selected crew accuracy circles and inside/outside/boundary status account for GPS uncertainty. Stale or imprecise GPS cannot produce a confident fence result.
- Messaging and read-only open-unit details are reachable from crew cards.
- Geofence visualization does not change payroll or auto-clock-out rules. Arrival verification remains authoritative on the server.

Physical-device GPS, background sharing, and permissions still require device testing. Simulator CI verifies compilation, tests, and unsigned Release archives; it does not verify a physical crew's location.
