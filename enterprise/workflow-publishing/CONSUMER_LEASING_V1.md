# HALO Per-Consumer PostgreSQL Delivery Leasing

Adds a draft, database-backed worker queue with independent lease/attempt state for each (tenant,event,consumer). Workers for the same consumer claim at most one available row with PostgreSQL SKIP LOCKED. Completion, retry, dead-letter updates require matching tenant, event, consumer, owner, unexpired lease and token.

Migration 010 creates a dedicated NOLOGIN dispatcher DB role; it is global by design and must be exclusively used by trusted internal dispatch. It is NOT acceptable for arbitrary user SQL or direct customer access. No registration write path, transport destination, network call, Enforcer integration or credential exists.

Release blockers: CI/PostgreSQL integration pass, a server-verified tenant/consumer registry, atomic fanout SQL adapter, revocation checks at dispatch, signed callbacks, consumer-side idempotency, production credentials, RLS security review, and delivery telemetry.
