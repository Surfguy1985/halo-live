# Isolated PostgreSQL work-item execution foundation

Proposed migration `005_work_item_execution.sql` creates four tenant-scoped tables: jobs, idempotency receipts, immutable transition audit and transactional event outbox. It enables FORCE RLS and grants the pre-existing executor role minimal read/write capabilities.

`PostgresExecutionStore` runs each transition with a tenant-local setting, `SET LOCAL ROLE`, serializable transaction, row lock, compare-and-swap revision update and atomic writes to audit, outbox and receipt. Integration tests use only an explicitly named `halo_test_*` database, and cover distinct-key races, replay, tenant separation, rollback and fail-closed RLS.

**Not production complete:** A trusted API and evidence verification boundary, retry policy for serialization failures, provisioned restricted database login, identity-aware DB access controls, trusted job seeding, background outbox consumer with deduplication, retention policies and security review. RLS based on custom tenant settings is defense-in-depth and does not protect an attacker who controls arbitrary SQL in the runtime session. Existing HALO/Enforcer remain disconnected.
