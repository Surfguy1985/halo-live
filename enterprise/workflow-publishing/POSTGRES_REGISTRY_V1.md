# Postgres integration management v1 (draft)

Implements transaction-local internal role and tenant RLS, per-tenant/consumer advisory locking (including first insert), revision-guarded upsert, immutable audit insertion, and idempotency receipts. Disposable PostgreSQL integration test exercises competing updates, tenant isolation, replay, and fail-closed RLS.

Not connected to any live endpoint or transport. **Must address before production:** strict trusted membership checks, dedicated restricted connection pool, real authenticated updated_by actor in registration row, canonical JSON idempotency fingerprint (current service comparison is order-sensitive), policy audit, transaction retry strategy, dispatch-time revocation, and CI green. Never give client connections the registry manager role or arbitrary SQL access.
