# HALO 1.0 — App Store Submission Package

## App identity
- App name: HALO
- Bundle ID: com.archangel.halofield
- Version: 1.0.0
- Build: 2
- Primary category: Business
- Minimum iOS: 17.0
- Device family: iPhone
- Tracking: No
- Advertising: No
- In-app purchases: None

## Product description
HALO is a field operations application for authorized property-service teams. Assigned crew members receive today's jobs, verify arrival with live photo and GPS, document before/after work, complete authorized checklists, communicate with the office, and submit work for review. Authorized office users can access live operational status.

## App Review notes
HALO does not offer public account registration. Access is provisioned by an organization's HALO administrator using a revocable activation credential tied to a crew identity and organization.

Review account/device:
1. Obtain a current App Review activation credential from the release owner before submission.
2. Launch HALO.
3. Enter the provided activation credential on the activation screen.
4. Review Today, Jobs, HALO messaging, photo/GPS check-in, proof capture, offline sync, and (for an office credential) Live Operations.

Location behavior:
- Location is used to verify arrival at an assigned property.
- Background location is used only while a worker explicitly shares an active live crew-location session with the office.
- Public property views suppress stale GPS.
- HALO does not use location for advertising or cross-app tracking.

Camera/photo behavior:
- Camera is used for verified arrival and work documentation.
- Photo Library access lets an authorized worker attach existing job evidence.
- Message and proof media are stored privately and authorized views use expiring signed access.

Notifications:
- Push notifications are used for operational assignments, messages, rework, and job updates.

AI:
- HALO may generate an operational closeout summary from unit records and unit-related conversation.
- Structured operational records remain authoritative.
- Personal/off-topic conversation is excluded from the permanent closeout summary.
- Exact conversation history is restricted to administrators and retained for 30 days before scheduled deletion.

## App privacy declaration source of truth
The binary privacy manifest declares:
- Precise Location — linked to the user, App Functionality
- Photos or Videos — linked to the user, App Functionality
- User ID — linked to the user, App Functionality
- Tracking — false
- UserDefaults required-reason API — CA92.1

Before submission, App Store Connect privacy answers must match the production system and this manifest. Do not mark HALO as collecting data for advertising, third-party advertising, or tracking.

## Required URLs before submission
App Store Connect requires a publicly accessible Privacy Policy URL. Configure:
- Privacy Policy URL: REQUIRED — release owner must supply/publish final legal URL
- Support URL: REQUIRED FOR RELEASE OPERATIONS — release owner must supply/publish support page
- Marketing URL: optional
- Privacy Choices URL: optional unless HALO publishes a dedicated data-rights page

## Screenshots to capture from a release build
Capture current App Store-required iPhone screenshots from a physical/release-equivalent build:
1. Today briefing
2. Job detail
3. Photo + GPS check-in
4. Before/after proof
5. HALO messaging
6. Live Operations (authorized office credential)

Do not use simulator-only debug fingerprints in store screenshots.

## Release-owner gates that cannot be completed from source code
- Apple Developer team / App Store Connect app record
- Distribution signing certificate and provisioning profile
- Production APNs key configured on backend
- Final Privacy Policy and Support URLs
- App Store Connect privacy questionnaire
- Age rating questionnaire
- Availability/territories
- App Review contact details
- Review activation credential
- Final screenshots
- Signed archive upload / TestFlight processing
- Physical-device verification of production push and background location

## Release command
Run:
```bash
cd NativeiOS
xcodegen generate
bash scripts/app-store-readiness.sh
xcodebuild test -project HaloField.xcodeproj -scheme HaloField -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

CI also builds an unsigned generic-iOS Release archive to catch archive-only failures before signing.
