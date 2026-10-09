# HALO RC1 — Cross-runtime CI trigger matrix

The native iOS and enterprise PostgreSQL workflows are **independent gates**. A passing backend run does not imply an iOS build passed, and vice versa.

| Changed surface | Native iOS CI | Workflow PostgreSQL CI |
|---|---|---|
| Native iOS app and tests | Yes | Only when Swift workflow contract files change |
| Swift workflow domain/proposal and wire fixture generator | Yes | Yes |
| Native staging publishing transport | Yes | Yes |
| Backend publish layout, handler, publisher | Yes | Yes |
| Shared Swift wire JSON fixture and Node interoperability test | Yes | Yes |
| Other enterprise workflow implementation and migrations | No (unless contract surface above) | Yes |
| Native iOS workflow YAML | Yes | No |
| Backend PostgreSQL workflow YAML | No | Yes |

## Required evidence before integration

1. For native changes: macOS `swiftc` fixture check, compiled Swift-to-Node handler test, iOS simulator XCTest, and unsigned Release archive.
2. For backend changes: JavaScript syntax preflight, Node domain suite, and real disposable PostgreSQL integration suite.
3. For shared contract changes: **both** CI jobs on the exact PR SHA. Never infer coverage from another SHA or from a skipped job.
4. For security: revoked membership, wrong tenant, invalid JWT, stale revision, idempotency replay, RLS and audit tests must pass.
5. For a production release: manual iPhone smoke, TLS/JWKS/issuer and tenant membership verification, observability, rollback and signoff. None is implied by these CI jobs.

## Merge and deployment controls

All workstreams target `release/halo-workflow-rc1-candidate` as draft PRs. The release branch is **not production**. No automatic merges, Base44 cutover, live Enforcer changes or production deployment. Review overlapping paths before combining PRs.

## Limitations

GitHub path filters control whether a workflow is **scheduled**, not whether every dependency is covered. If a new shared schema file is introduced, add it to this matrix and both workflow filters in the same PR. Native CI currently requires macOS runners and can take longer than backend CI.
