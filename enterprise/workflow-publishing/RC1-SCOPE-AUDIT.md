# HALO RC1 — release-scope audit

Audit basis: GitHub comparison `main...release/halo-workflow-rc1-candidate` at `9c220ae54b3cf219b6315491d12eba1fc68ace2d`.

## Scope confirmed
- **531 commits ahead of main**, 0 behind.
- **220 changed files**: 140 under `enterprise/`, 78 under `NativeiOS/`, and 2 GitHub Actions workflows.
- The current successful PostgreSQL workflow (run `37937564344`) proves only the explicitly configured `enterprise/workflow-publishing` test suite. It does **not** validate the 78 native iOS files or the full 531-commit history.
- This branch is a snapshot of a stacked development history, **not** an independently reviewed or deployable release.
- No JavaScript dependency lockfile appeared among the changed files in this comparison; verify the full repository tree and lock dependency versions before relying on reproducible CI builds.

## Release blockers and evidence required

1. [ ] Review the **complete** 531-commit and 220-file cumulative diff against `main`, including third-party code, generated assets, secrets scanning, ownership, data handling, and licensing.
2. [ ] Establish commit-specific Swift/Xcode build and XCTest results for the actual release SHA; validate signing entitlements and permissions.
3. [ ] Freeze and review all dependency versions, lockfiles and supply-chain scanning.
4. [ ] Prove all SQL migrations are safe for a representative existing schema, with tenant-isolation/RLS tests, and rehearsed backup/recovery.
5. [ ] Produce Swift ↔ backend API compatibility, auth/tenancy, idempotency and offline-retry contract evidence.
6. [ ] Run a staging-only, failure-injected end-to-end flow with all outbound side effects disabled.
7. [ ] Obtain independent code/security review and an explicit merge/deploy approval.

## Release controls

- Treat `Workflow PostgreSQL Integration` as a **component test**, not a platform-wide green release gate.
- Keep the branch isolated. Do not automatically merge the stacked PRs or promote to production.
- Require explicit evidence for each blocker; checkboxes are not self-certifying.
