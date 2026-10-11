# HALO Native Marketplace — Figma → SwiftUI/Xcode (draft)

## Source of truth

- Approved HALO 84-screen Figma suite: https://www.figma.com/design/tsF6XdJRXjS7gTiCGYt4v5
- Implemented in this slice: Figma **73 · Open Jobs · Map** (node `8:2`), **74 · Industry Filters** (node `8:64`) and **76 · Job Opportunity · Detail** (node `8:192`).
- Native implementation: `HaloMarketplaceExploreView`, `HaloMarketplaceDetailView`, scoped `HaloMarketplaceDesign`, industry-neutral filter model, MapKit annotations and XCTest.
- Exact original silver-wing PNG and 900px wordmark recovered from the approved HALO branded design artifact; committed as `HALOWing.imageset/HALO-Wing.png` and `HALOWordmark.imageset/HALO-Wordmark.png`, not recreated with SF Symbols or a temporary remote URL.
- Match to the Figma palette: `#F7F9FC` pearl, `#142031` ink, `#152338` midnight, `#657489` slate, `#416A9A` steel blue, `#187D66` earnings, `#E8EEE9` map, `#E3E9F0` border. Native SF text metrics approximate Figma Inter until font licensing/install is resolved. **Do not distribute font files.**
- New marketplace styles remain scoped; existing HALO Field dark work-management flows are not restyled or overwritten.

## Open in Xcode

On a Mac with Xcode and XcodeGen:

```bash
git fetch origin
git switch feature/halo-native-figma-marketplace-v1
brew install xcodegen
cd NativeiOS
xcodegen generate
open HaloField.xcodeproj
```

Run the **HaloField** scheme on an iOS 17+ simulator/device. In **Debug** builds, activate HALO Field's existing preview or use a valid Field activation and go to:

**Jobs → Explore HALO Marketplace**.

The screen also has a direct SwiftUI preview: `HaloMarketplaceExploreView.swift` → Canvas. The marketplace's `#Preview` intentionally uses clearly labeled sample opportunity data, not a real feed. Existing tabs, activation, attendance, proof and assignment operations are untouched.

The XcodeGen `project.yml` recursively includes `HaloField` and `HaloFieldTests`, so the new Swift files and tests are picked up when the project is regenerated. The exact original PNGs are included through the asset catalog.

## Backend compatibility (not yet activated)

`HaloMarketplaceAPIClient` is a native, opt-in HTTPS interface aligned to `Surfguy1985/halo-platform` draft PR #124:

- `GET /v1/marketplace/opportunities`: authenticated, strictly validated public opportunities; never use demo records on errors
- `POST /v1/marketplace/requests/prepare`: server-generated, durable principal/job attempt key returned before first POST
- `POST /v1/marketplace/opportunities/:id/requests`: requires newly reserved key, never automatically retries an ambiguous outcome
- `POST /v1/marketplace/requests/reconcile`: read-only lookup using the **original** key; a 404 never authorizes a new request

**Do not pass the existing HALO Field Base44 activation token as an OIDC marketplace bearer.** A separately reviewed trusted identity provider, current capabilities/revocation, admission service, HTTPS ingress, worker eligibility, cross-device backend tests and release authorization are still required. This branch does not configure a live API origin or start marketplace network traffic from the UI.

The preview detail button is disabled. A job request is **not** an assignment. Preview locations, amounts and scope are illustrative only.

## Verification gates

Native development files are committed but have **not been compiled with Xcode** in this environment (Xcode is only available on macOS). Before merging:

1. Run XcodeGen, `xcodebuild` test on `HaloField` and `HaloFieldTests`, compare map/detail screen screenshots against Figma nodes 8:2/8:192 on 393pt-width iPhone.
2. Check exact wing/wordmark asset geometry and light-background legibility, VoiceOver labels, Dynamic Type and reduced-motion behavior; test with real photo assets when backend authorizes media.
3. Verify the cross-repository opportunity API contracts, full Node 24.21/Postgres 17 security suite, durable reservation concurrency, auth and session-switch isolation in a disposable staging environment. GitHub Actions issue #122 and the combined `pnpm-lock.yaml` in backend PR #124 remain release blockers.
4. Keep `#if DEBUG` gate until all security and approval checks pass. No Base44, Enforcer, production, or default branch modifications.

This PR is a **native Xcode design/contract integration slice**, not a production-ready end-to-end marketplace.
