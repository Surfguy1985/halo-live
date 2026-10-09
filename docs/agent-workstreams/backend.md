# HALO RC1 workstream — Backend and staging bootstrap

Issue: https://github.com/Surfguy1985/halo-live/issues/34
Branch: `agents/halo-backend-rc1`
Baseline: `3b9e4916e59e6b8dbdd54337236c9491eeb9e488`
PR base: `release/halo-workflow-rc1-candidate` (draft only)
Owned surface: enterprise/workflow-publishing/**

## Initial implementation deliverables
1. Disposable PostgreSQL staging bootstrap and teardown with halo_test_* hard stop
2. TLS/issuer/audience/membership readiness checklist; do not deploy automatically
3. Deterministic HTTP publishing, revision, audit and idempotency smoke tests

## Required verification
npm test; npm run test:postgres; workflow PostgreSQL GitHub Actions

## Integration gates
- Preserve the versioned workflow publish contract, expected revision, idempotency and tenant authority.
- No merge to `main`, `ios-swift-native-v1`, or release candidate without reviewed CI evidence.
- Never touch production Base44 BackOffice Copy or Enforcer-v3 portal.
- No production secrets, credentials, deployments or cutover.
- Treat all side-effecting retries as unsafe until reconciled by idempotency and revision.
- Coordinate shared files and breaking schema changes through GitHub issue discussion.

## Current state
Workstream branch created with an initial scope document. This is a kickoff artifact, **not evidence of a running autonomous agent or completed implementation**.
