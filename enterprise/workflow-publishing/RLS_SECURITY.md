# RLS deployment contract — isolated HALO workflow publisher

Status: proposed security layer, not deployed. This migration adds restricted table privileges and tenant-based RLS. It does **not** make an exposed SQL connection safe for arbitrary users.

## Provisioning (DBA-owned)
1. Create `halo_workflow_executor` as `NOLOGIN NOBYPASSRLS` (role must not own workflow tables).
2. Use a trusted backend login role that is a member of `halo_workflow_executor`; that login must NOT own the tables and must NOT have `BYPASSRLS`. Do not share this credential with Swift, browser, Base44 clients, vendors or customers.
3. Apply migrations 001 then 002 under a privileged DBA migration identity, separate from the runtime role.
4. Validate `SELECT row_security_active('halo_workflow.template_heads'::regclass)` is true under the runtime login.
5. Grant minimum permissions only. Never give runtime `DELETE`, `TRUNCATE`, `ALTER`, `CREATE`, `BYPASSRLS`, membership in table-owner roles, or arbitrary SQL execution to end users.

## Tenant provenance
`PostgresWorkflowStore` sets `halo.tenant_id` using `set_config(..., true)` inside a transaction. The value MUST be derived by authenticated, authorized server middleware. PostgreSQL custom GUCs can be set by users of a SQL connection, so this policy is defense in depth against accidental cross-tenant query mistakes, **not** protection against an attacker controlling the runtime SQL connection.

A production hardened deployment should use DB credential isolation, signed/trusted identity at the API boundary, mandatory tenant filtering, row-level policies, and strict SQL access restrictions. For strong resistance to SQL injection that can arbitrarily set GUCs, use verified security-definer entrypoints with no direct table grants, or dedicated tenant credentials/databases after specialist review.

## Tests
- `npm test` runs domain and SQL protocol tests.
- `npm run test:postgres` runs PostgreSQL integration tests only against an explicitly named `halo_test_*` database, creates the restricted role, applies both migrations, checks tenant invisibility and wrong-tenant insert denial.
- GitHub Actions CI provisions an ephemeral PostgreSQL 16 instance.
- Tests do not establish production authentication, production connection hardening, or pen-test readiness.

## Release blockers
Do not connect to live Base44/Enforcer until server authentication, API rate limiting, restricted runtime credentials, RLS checks under actual runtime login, app-specific tenant authorization, concurrent retries, and security review all pass.
