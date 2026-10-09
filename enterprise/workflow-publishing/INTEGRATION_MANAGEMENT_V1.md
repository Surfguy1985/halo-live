# Integration management v1 — isolated service contract

Implements an injected transaction contract for create/update/disable with tenant authorization, optimistic revision fencing, idempotency receipts, and immutable audit proposals. A dedicated schema migration creates protected audit and receipt tables.

**Not production ready.** Requires real PostgreSQL adapter, row lock and first-write uniqueness, authorization at DB session boundary, canonical request fingerprinting (the current JSON equality check is order-sensitive), complete SQL concurrency tests, trusted admin API, immediate revocation enforcement in dispatch, and security review. No live Enforcer or Base44 mutation.
