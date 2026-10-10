# HALO historical build order

Status: **locked**. This is the canonical execution order recovered from the original HALO build history and the RC1 release gate. Do not skip, reorder, or treat a later phase as complete while an earlier phase lacks evidence.

## Original five-phase sequence

1. [x] **Phase 1 — Backend automated testing**
   - The workflow backend established a passing JavaScript, domain/adapter, and PostgreSQL 16 baseline.
   - Historical evidence: GitHub Actions run `37936784629` at `4acb25cd1579d7339078c536a90e7e775f6a7b45`.
2. [x] **Phase 2 — Release-readiness requirements documented**
   - `RELEASE-CANDIDATE-1.md` defines the release blockers and safe promotion sequence.
3. [x] **Phase 3 — Consolidate stacked GitHub branches**
   - The stacked history was placed on the isolated `release/halo-workflow-rc1-candidate` line rather than merged to `main`.
   - The current cumulative 555-commit/261-file comparison is recorded in `RC1-FULL-STACK-AUDIT.md`.
4. [x] **Phase 4 — Validate Swift/API integration**
   - Local contract, authentication, tenancy, idempotency, revision-conflict, and response-validation baselines were implemented and tested.
   - This phase establishes the pre-staging contract baseline. Verification against an actually deployed staging API remains a Phase 5 evidence gate.
5. [ ] **Phase 5 — Staging deployment and failure testing**
   - This is the active phase. Follow the ordered promotion sequence below without advancing early.

## Phase 5 ordered promotion sequence

This is the safe promotion order already defined in `RELEASE-CANDIDATE-1.md`:

1. [x] Review the full stacked history and place it on an isolated release branch without changing production.
2. [ ] Run the entire backend suite on the exact final release SHA, including PostgreSQL 16 and all required branch-protection checks.
3. [ ] Deploy that exact SHA to staging only, with no production credentials, payments, webhooks, Enforcer execution, or dispatch side effects.
4. [ ] Rehearse backups, ordered migrations, restore, and rollback; collect observability evidence.
5. [ ] Sign off integration and security tests, including Swift against the deployed staging API, and obtain explicit production-change authorization.
6. [ ] Roll out incrementally behind feature flags with documented stop and rollback criteria.

## Evidence gates inside the sequence

The following requirements remain mandatory at their applicable step. They do not authorize changing the order above.

- Exact-release-SHA Swift/Xcode build, XCTest, signing-entitlement, and permission evidence.
- Reproducible dependency installation, vulnerability scanning, and license approval. The technical gate is complete; Hippocratic-2.1 product/legal acceptance or replacement remains open.
- Empty and representative-schema PostgreSQL migration rehearsals, RLS/tenant-isolation proof, and backup recovery.
- Swift/backend authentication, tenancy, idempotency, conflict, transport-failure, and offline-recovery evidence against staging.
- Multi-actor financial controls and explicit review of the Enforcer boundary.
- Operational controls, structured observability, load/failure drills, and all outbound side effects disabled during staging proof.
- Independent code/security review and explicit merge/deploy approval.

## Current checkpoint

The next permitted build action is **Phase 5, step 2**: publish the exact candidate SHA to its isolated GitHub branch and run fresh required CI on that SHA. Do not begin a staging deployment or claim migration-rehearsal completion before this gate passes.

Production, `main`, Base44, live payments, webhooks, dispatch, and Enforcer remain out of scope until the ordered gates and explicit authorization are complete.
