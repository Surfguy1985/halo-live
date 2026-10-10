# HALO isolated CI staging gate

`staging-promotion.yml` is the Phase 5 exact-SHA promotion gate. It does not
deploy production, a public preview, Base44, payments, webhooks, Enforcer, or
outbound dispatch.

## Required order

For a push to `codex/halo-enterprise-reconciliation-rc1`, the workflow runs the
reusable web, PostgreSQL 16, and native iOS gates against the same Git commit.
The isolated staging job can start only when all three succeed and the commit
message contains `[staging]`. The recovery rehearsal can start only after that
isolated staging job succeeds. The Swift HTTPS security signoff can start only
after the recovery rehearsal succeeds.

The job uses a fresh PostgreSQL database and Redis instance pinned by image
digest, synthetic local credentials, a generated RSA key pair, and a loopback
HTTP listener on an ephemeral port. Checkout credentials are not persisted;
the job has read-only repository permission and receives no repository secrets,
GitHub environment, or OIDC authority.

## Fail-closed boundaries

- `staging-ci-admission.mjs` is separate from real staging admission and accepts
  only the exact repository, branch, SHA, synthetic hosts, disposable database,
  loopback services, and disabled side-effect flags.
- Ordered migrations 001–024 create separate NOINHERIT workflow and identity
  logins. Actor membership reads are RLS-scoped; the login has no direct table
  grant.
- Before binding, `staging-principal-attestation.mjs` verifies actual session
  users, database, TLS expectation, safe role attributes, exact memberships,
  and the absence of direct application-table ACLs.
- The canonical Swift fixture proves publish, exact replay, reconciliation,
  missing receipt, idempotency conflict, revision conflict, request-ID mismatch,
  invalid JWT, tenant denial, invalid schema, membership revocation, dependency
  readiness failure, one durable revision/audit/receipt, and zero dispatch or
  integration side effects.

## Swift HTTPS security signoff

The final job compiles the production `HaloStagingWorkflowClient` and connects
it to the actual isolated backend through `workflow.staging.invalid`. The
hostname is mapped to loopback only inside the disposable runner. An ephemeral
CA and leaf certificate are generated for that exact DNS name, the CA is added
to the runner trust store for the job, and it is removed in an `always()`
cleanup step. The Swift client uses ordinary `URLSession` trust evaluation; it
has no certificate bypass or redirect override.

The signoff proves a TLS 1.2-or-newer handshake, zero redirects, successful
publish, exact idempotent replay, read-only reconciliation, invalid-token
rejection, revision conflict handling, one durable revision/audit/idempotency
record, and zero outbound side effects. Its additional admission marker cannot
weaken the base exact-repository, branch, SHA, service, or feature-disable
constraints.

The trusted hostname and certificate are synthetic and runner-local. This is
integration/security evidence for the isolated Phase 5 staging boundary, not a
public or production certificate, real customer environment, or production
change authorization.

## Recovery rehearsal

`staging-ci-rehearsal.mjs` uses another fresh PostgreSQL 16 service and a
separate exact admission marker. It applies migrations 001–023, seeds a
representative synthetic baseline, writes a custom-format `pg_dump` backup with
the same pinned PostgreSQL image, applies migration 024, proves actor-scoped
RLS, rolls 024 back, and verifies that the baseline is unchanged. It then
restores the persisted backup into a separate database, compares the complete
manifest, reapplies 024, rechecks RLS, and deletes the backup and restore
database during cleanup.

The rehearsal contains no customer data and does not claim production backup
or disaster-recovery readiness. Representative-volume recovery timing, retained
encrypted backups, and operational restore authorization remain later gates.
