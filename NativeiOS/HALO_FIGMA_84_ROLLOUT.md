# HALO — 84-Screen Figma → Native SwiftUI Upgrade

Source: [Approved HALO 84-screen Figma suite](https://www.figma.com/design/tsF6XdJRXjS7gTiCGYt4v5)  
Native project: `NativeiOS/project.yml` (XcodeGen) / `HaloField` iOS 17+ target  
Isolated draft: `feature/halo-native-figma-marketplace-v1`; existing field operations and production stay unchanged.

## Reality of screen coverage

`HaloFigmaScreenCatalog.swift` contains **all 84 exact Figma frame IDs**, in numerical order. This is a traceability requirement, not a claim that 84 complete screens exist.

| Figma IDs | Flow | Current native implementation |
|---|---|---|
| 01–09 | Entry, trust, account | Figma references catalogued; separate SwiftUI ports and identity APIs pending |
| 10–20 | Workspace onboarding / role and industry setup | Catalogued; distinct native role/industry flows pending |
| 21–32 | Template marketplace, arrangeable workflow builder, triggers, simulations, publishing | Catalogued; existing unrelated native workflow components may be reusable but these 12 Figma screens are **not** ported |
| 33–44 | Executive briefing, live map, operations, dispatch, creation, evidence | Catalogued; existing HALO Field screens remain available, but have **not** been visually reworked to match these 12 Figma screens |
| 45–54 | Crew, acceptance, navigation, verification, execution | Catalogued; existing HALO Field workflows not yet ported to the approved 10-screen Figma treatments |
| 55–62 | Quotes, approvals, invoices, payments, payouts, compliance | Catalogued; new Figma UI and full financial-service verification pending |
| 63–70 | HALO intelligence, Enforcer, exceptions, analytics and audit | Catalogued; distinct Figma screen ports and verified Enforcer integrations pending |
| 71–72 | Alerts / settings | Catalogued; screen-specific Figma ports pending |
| **73–84** | Marketplace map, filters, list, opportunity details, apply, accepted state, saved, contractor availability and industry landing pages | **12 native SwiftUI preview routes** built with shared real components; clearly illustrative and not backend-authorized |

The new design gallery at **Jobs → HALO 84-Screen Figma Library** appears only in **Debug builds**. Design references 1–72 navigate to the *real Figma frames*, not fabricated functional placeholders. IDs 73–84 open native MapKit/SwiftUI previews.

Native files include `HaloFigmaScreenCatalog`, `HaloFigmaScreenLibraryView`, `HaloMarketplaceExploreView`, `HaloMarketplaceDetailView`, `HaloMarketplaceJourneyView`, native models/theme, original asset-catalog wing/wordmark, gateway client, and XCTest. XcodeGen's `HaloField` source directory automatically includes new Swift files.

## Reuse the EXACT brand

- Source theme: pearl `#F7F9FC`, ink `#142031`, midnight `#152338`, slate `#657489`, steel blue `#416A9A`, earnings green `#187D66`.
- Original HALO metallic wing and silver wordmark PNG are committed to Xcode `.xcassets` with no temporary Figma URL.
- No generated/surrogate logos, no unlicensed font redistribution. System text metrics still require comparison against the Figma Inter design on an iPhone simulator.
- Photo/media treatment on later screens must use the exact approved Figma originals plus dynamic job imagery; do not substitute screenshots or invent customer-approved imagery.

## Backend truth and release gates

**HALO is not a fully built, integrated, release-verified enterprise backend.**

The older `halo-live` repository contains a working HALO Field/Back Office application and numerous **draft** workflow/dispatch/reconciliation/financial branches. Those branches do **not** equal a single integrated, deployed and security-certified multi-industry operating system.

The separate `halo-platform` repository has a draft marketplace+PostgreSQL service integration in PR #124, plus other stacked drafts for worker verification, eligibility, incidents and trusted JWT boundaries. **Outstanding:** a merged and runnable backend, pinned dependency lockfile resolution, PostgreSQL 17 security/concurrency tests, OIDC integration, user/device cross-session verification, admission/rate limiting, staging E2E, CI, event/notification integration, financial settlement and operational runbooks.

**Native Field activation is NOT the same as a marketplace JWT.** The opt-in `HaloMarketplaceAPIClient` is intentionally not injected with any live tokens or endpoints. Native preview jobs are illustrative, not verified/assigned/paid. Demo application and assigned-state buttons are disabled. Contractor availability does not update dispatch.

### Gate before any production promotion

1. macOS runner successfully generates Xcode project, compiles the iPhone app, runs XCTest and accessibility checks with original artwork.
2. Native authentication/marketplace gateway is reviewed against the **actual** PostgreSQL 17 and OIDC service contracts; no Base44 activation-token reuse.
3. Backend complete dependency pinning, migrations, RLS/concurrency, account-switch and lost-POST recovery verified in staging.
4. Pixel-level review against all 84 approved Figma frames, screen-by-screen; adapt safe areas, Dynamic Type, VoiceOver, keyboard and reduced motion. Screens 1–72 must actually be ported.
5. Explicit security/release signoff, then controlled merge/deploy. Never treat an Xcode preview, an API mock or an authored test as release certification.

## Xcode commands

From the new native feature branch on a Mac:

```bash
git fetch origin
git switch feature/halo-native-figma-marketplace-v1
brew install xcodegen
cd NativeiOS
xcodegen generate
open HaloField.xcodeproj
```

Run scheme `HaloField` in Debug, open **Jobs → HALO 84-Screen Figma Library** or **Jobs → Explore HALO Marketplace**. The library will show all numbered designs, marking unfinished ports. No direct merge or live endpoint activation is implied.

**Implementation sequence after native CI:** 01–09 entry/trust → 10–20 onboarding → 21–32 builder → 33–44 operations → 45–54 crew → 55–62 finance → 63–70 intelligence/governance → 71–72 notifications/settings. Prioritize backend contracts and tests before implementing mutating UI.
