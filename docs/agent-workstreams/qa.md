# HALO RC1 workstream — QA and release gates

Issue: https://github.com/Surfguy1985/halo-live/issues/38
Branch: `agents/halo-qa-rc1`
Baseline: `3b9e4916e59e6b8dbdd54337236c9491eeb9e488`
PR base: `release/halo-workflow-rc1-candidate` (draft only)
Owned surface: CI, test harness, release evidence

## Initial implementation deliverables
1. Risk-to-test traceability and independent CI gate matrix
2. Flake/retry policy; no skipped-test green claims
3. RC1 release checklist with rollback, device verification and production signoff

## Required verification
Native iOS CI and Workflow PostgreSQL Integration GitHub Actions

## Integration gates
- Preserve the versioned workflow publish contract, expected revision, idempotency and tenant authority.
- No merge to `main`, `ios-swift-native-v1`, or release candidate without reviewed CI evidence.
- Never touch production Base44 BackOffice Copy or Enforcer-v3 portal.
- No production secrets, credentials, deployments or cutover.
- Treat all side-effecting retries as unsafe until reconciled by idempotency and revision.
- Coordinate shared files and breaking schema changes through GitHub issue discussion.

## Current state
Workstream branch created with an initial scope document. This is a kickoff artifact, **not evidence of a running autonomous agent or completed implementation**.
