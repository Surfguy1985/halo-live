# HALO RC1 workstream — Swift iOS staging publishing

Issue: https://github.com/Surfguy1985/halo-live/issues/35
Branch: `agents/halo-ios-rc1`
Baseline: `3b9e4916e59e6b8dbdd54337236c9491eeb9e488`
PR base: `release/halo-workflow-rc1-candidate` (draft only)
Owned surface: NativeiOS/**

## Initial implementation deliverables
1. Staging-only configuration boundary; no Base44 cutover
2. Fail-closed request handling, unknown outcome reconciliation, no unsafe retry
3. Swift JSONEncoder ↔ Node golden fixture parity and XCTest coverage

## Required verification
Native iOS CI: Swift fixture, XCTest and unsigned archive

## Integration gates
- Preserve the versioned workflow publish contract, expected revision, idempotency and tenant authority.
- No merge to `main`, `ios-swift-native-v1`, or release candidate without reviewed CI evidence.
- Never touch production Base44 BackOffice Copy or Enforcer-v3 portal.
- No production secrets, credentials, deployments or cutover.
- Treat all side-effecting retries as unsafe until reconciled by idempotency and revision.
- Coordinate shared files and breaking schema changes through GitHub issue discussion.

## Current state
Workstream branch created with an initial scope document. This is a kickoff artifact, **not evidence of a running autonomous agent or completed implementation**.
