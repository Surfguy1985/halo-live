# HALO isolated CI staging gate

`staging-promotion.yml` is the Phase 5 exact-SHA promotion gate. It does not
deploy production, a public preview, Base44, payments, webhooks, Enforcer, or
outbound dispatch.

## Required order

For a push to `codex/halo-enterprise-reconciliation-rc1`, the workflow runs the
reusable web, PostgreSQL 16, and native iOS gates against the same Git commit.
The isolated staging job can start only when all three succeed and the commit
message contains `[staging]`.

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

This gate proves the backend contract over loopback HTTP. It does **not** prove
the Swift client's final HTTPS deployment path, certificate chain, redirects,
or a real `stage`/`staging` hostname; those remain later Phase 5 evidence.
