# HALO workflow backend — Release Candidate 1 gate

Status: **candidate only**. Passing workflow CI is necessary, not sufficient, for a release.

## Verified automated baseline

- GitHub Actions **Workflow PostgreSQL Integration**, run `37936784629`, succeeded at commit `4acb25cd1579d7339078c536a90e7e775f6a7b45`.
- Workflow steps: JavaScript syntax preflight, domain/adapter tests, and isolated PostgreSQL integration tests.
- Integration database: disposable `halo_test_workflow` on PostgreSQL 16. This is **not** a production or staging deployment.
- The test command is `npm run test:postgres --prefix enterprise/workflow-publishing`. CI runs the commands sequentially; a green result covers only tests invoked by this command.

## Required before an RC1 release or production enablement

- [ ] **Stacked PR ancestry**: review and land the ancestor PRs in order. PR #33 is based on `feature/workflow-financial-approval-store-v1` (PR #32), not the default branch. Do not squash or merge PR #33 directly into production without reviewing the complete stacked diff.
- [ ] **Fresh CI**: all required branch-protection checks must pass on the exact final merge commit, not merely on the current draft branch.
- [ ] **Reproducible install**: commit and review a dependency lockfile, switch CI to `npm ci` where appropriate, and scan dependencies for vulnerabilities and license obligations.
- [ ] **Migration staging rehearsal**: apply the complete ordered migration set to an empty staging DB and to a staged copy of a representative existing schema; test role grants, forced RLS, tenant isolation, and repeatable deploy behavior.
- [ ] **Backup and rollback plan**: confirm a database recovery point and document reversible application rollout. PostgreSQL destructive/irreversible schema migrations may require restore/forward-fix rather than `DOWN` SQL.
- [ ] **Swift/API contract checks**: verify native iOS authentication, tenant-scoped requests, idempotency, revision conflicts, transport failures, and reconnect behavior against deployed staging APIs.
- [ ] **Financial controls**: review external receipt verification and dual approval in a genuine multi-actor environment; never automatically replay an uncertain financial action.
- [ ] **Enforcer boundary**: integration must be separately reviewed and explicitly authorized. Draft backend code does not authorize live Enforcer execution.
- [ ] **Operational controls**: configure service credentials, secret rotation, structured audit logs, alerts, SLOs, backpressure, queue dead-letter response, rate limiting, and on-call ownership.
- [ ] **Load/failure drills**: cover concurrent workers, dropped DB connections, delayed retries, duplicate event delivery, network partitions, clock skew, and a simulated failover.
- [ ] **Deployment authorization**: obtain an explicit decision to merge and/or deploy; do not infer permission from CI passing.

## Safe promotion sequence

1. Review full stacked history and merge into an isolated release branch through normal GitHub protections.
2. Run the entire backend suite on the resulting release SHA, including PostgreSQL 16.
3. Deploy to **staging only** with no production credentials, payments, webhooks, or dispatch side effects.
4. Rehearse backups, migrations, restore and rollback procedures; collect observability evidence.
5. Sign off integration/security tests and obtain an explicit production-change authorization.
6. Roll out incrementally using feature flags, with a documented stop/rollback criterion.

## Explicit exclusions

This gate does not establish full HALO, Swift/iOS, Base44, Enforcer, operational security, or production readiness. CI success does **not** mean application code was deployed.
