# HALO RC1 — release-scope audit

Original audit basis: GitHub comparison `main...release/halo-workflow-rc1-candidate` at `9c220ae54b3cf219b6315491d12eba1fc68ace2d`.

Current cumulative audit: `origin/main` at `905a6857348e4f9f18d19ec3b4c2d0c851050051` through `codex/halo-enterprise-reconciliation-rc1` at remediation commit `06b5a84`. See `RC1-FULL-STACK-AUDIT.md`.

## Scope confirmed
- **531 commits ahead of main**, 0 behind.
- **220 changed files**: 140 under `enterprise/`, 78 under `NativeiOS/`, and 2 GitHub Actions workflows.
- The current successful PostgreSQL workflow (run `37937564344`) proves only the explicitly configured `enterprise/workflow-publishing` test suite. It does **not** validate the 78 native iOS files or the full 531-commit history.
- This branch is a snapshot of a stacked development history, **not** an independently reviewed or deployable release.
- No JavaScript dependency lockfile appeared among the changed files in this comparison; verify the full repository tree and lock dependency versions before relying on reproducible CI builds.

## Release blockers and evidence required

1. [x] Review the current **complete** 555-commit and 261-file cumulative diff against `main`, including dependency licenses, generated/binary assets, high-confidence secrets scanning, ownership, migration safety, data boundaries, and helper-script behavior. Evidence and unresolved release decisions are recorded in `RC1-FULL-STACK-AUDIT.md`.
2. [ ] Establish commit-specific Swift/Xcode build and XCTest results for the actual release SHA; validate signing entitlements and permissions.
3. [x] Freeze dependency versions with npm lockfiles, enforce `npm ci`, and add repeatable vulnerability and license scanning. See `DEPENDENCY-SUPPLY-CHAIN.md`; production still requires explicit acceptance or replacement of the Hippocratic-2.1 map dependencies.
4. [ ] Prove all SQL migrations are safe for a representative existing schema, with tenant-isolation/RLS tests, and rehearsed backup/recovery.
5. [ ] Produce Swift ↔ backend API compatibility, auth/tenancy, idempotency and offline-retry contract evidence.
6. [ ] Run a staging-only, failure-injected end-to-end flow with all outbound side effects disabled.
7. [ ] Obtain independent code/security review and an explicit merge/deploy approval.

## Release controls

- Treat `Workflow PostgreSQL Integration` as a **component test**, not a platform-wide green release gate.
- Keep the branch isolated. Do not automatically merge the stacked PRs or promote to production.
- Require explicit evidence for each blocker; checkboxes are not self-certifying.
