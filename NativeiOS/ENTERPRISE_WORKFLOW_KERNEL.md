# HALO Enterprise Workflow Kernel — Phase 1

## Scope

The Swift file `HaloField/Domain/HaloWorkflowKernel.swift` is a **pure local decision preview**. It does not authenticate users, persist states, execute payments, dispatch workers, or replace the server's authorization decisions. The Base44/enforcer backend remains authoritative until a future independently tested workflow service is deployed.

## Invariants

1. Tenant ID must agree across template, work item and context.
2. Industry ID must agree across template, work item and context.
3. Template ID and version are pinned for the lifetime of a work item.
4. The actor must be identified and have at least one allowed role.
5. Transitions must exist from the work item's current state.
6. Evidence requirements must be satisfied to produce the candidate next state.
7. Terminal states cannot transition.

## Integration sequence (not yet connected)

1. Establish a versioned, server-defined JSON schema for workflow templates and block layouts, including stable block identifiers.
2. Add a server-side validator and rules engine with the same and additional authoritative controls: actor membership, signed evidence, permissions, replay/idempotency protections and transactional state updates.
3. Implement signed template fetch/cache in Swift, with tenant-scoped invalidation.
4. Render editable industry templates through reusable UI blocks: assignment, location, checklist, proof, pricing, approval, messaging and closeout.
5. Add a reconciliation path for offline mutation proposals, never trusting local evaluation as authorization.
6. Execute schema compatibility tests and end-to-end permission tests across property, construction and transport templates.
7. Roll out behind a feature flag to one internal tenant before any public or white-label activation.

## Verification

After generating the iOS project on macOS:

```bash
cd NativeiOS
xcodegen generate
xcodebuild test -project HaloField.xcodeproj -scheme HaloField -destination 'platform=iOS Simulator,name=iPhone 16'
```

Choose an installed simulator instead if iPhone 16 is unavailable. The new nine XCTest cases are in `HaloFieldTests/HaloWorkflowKernelTests.swift`. Do not label this implementation production-tested until simulator CI and server-side integration tests pass.

## Architectural decision

Swift/SwiftUI is the **native Apple client**, not the complete enterprise backend. The shared API, databases, authorization, audit trail, job execution and event processing must remain server-side so web, Android, Swift and partners enforce the same rules.
