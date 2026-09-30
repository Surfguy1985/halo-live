# HALO Field — Native iOS

This directory is an isolated SwiftUI rebuild of the HALO field experience. It lives only on the `ios-swift-native-v1` branch and does not replace or modify the existing React/Capacitor app.

## Product direction

The UX intentionally combines:
- Jobber: field-service information architecture
- DoorDash Dasher: one obvious action at a time
- Linear: calm operational density
- Superlist: elegant task interaction and motion
- Airtasker: task context and communication

HALO's native differentiator is a state-driven job flow:

`Scheduled → En Route → Arrived → Active → Proof → Review → Complete`

## Current native slice

- SwiftUI app shell with Today / Jobs / Halo / Me
- Premium Today screen and universal Field Job Card
- Job detail with live progress, task completion, proof cards and property notes
- State-driven sticky CTA
- API client foundation using the current HALO endpoint and `X-Halo-Role`
- Preview data for Xcode canvas / simulator work

## Generate the Xcode project

Install XcodeGen once:

```bash
brew install xcodegen
```

Then:

```bash
cd NativeiOS
xcodegen generate
open HaloField.xcodeproj
```

Target: iOS 17+, iPhone portrait first.

## Next build pass

1. Replace preview jobs with decoded live HALO jobs.
2. Native camera proof flow with metadata + upload queue.
3. Core Location check-in and route state.
4. Offline SwiftData queue.
5. MapKit job route.
6. Live Activities / Dynamic Island.
7. Push notifications.
8. Maintenance → Turns handoff.
