# HALO RC1 workstream — Industry-neutral workflow templates

Issue: https://github.com/Surfguy1985/halo-live/issues/37
Branch: `agents/halo-industry-rc1`
Baseline: `3b9e4916e59e6b8dbdd54337236c9491eeb9e488`
PR base: `release/halo-workflow-rc1-candidate` (draft only)
Owned surface: layout-contract and fixtures/tests

## Initial implementation deliverables
1. Schema v1-valid property, construction, transport and 1099 template fixtures
2. Typed config, deterministic ordering, role-visibility negative tests
3. Schema evolution notes without changing runtime authorization

## Required verification
layout-contract and fixture validation Node tests

## Integration gates
- Preserve the versioned workflow publish contract, expected revision, idempotency and tenant authority.
- No merge to `main`, `ios-swift-native-v1`, or release candidate without reviewed CI evidence.
- Never touch production Base44 BackOffice Copy or Enforcer-v3 portal.
- No production secrets, credentials, deployments or cutover.
- Treat all side-effecting retries as unsafe until reconciled by idempotency and revision.
- Coordinate shared files and breaking schema changes through GitHub issue discussion.

## Current state
Workstream branch created with an initial scope document. This is a kickoff artifact, **not evidence of a running autonomous agent or completed implementation**.
