# Consumer delivery fanout — isolated foundation

Each committed HALO event can create a distinct pending delivery record for every eligible, authorized consumer. Database uniqueness is `(tenant_id,event_id,consumer_id)`; one consumer's retries do not modify another's delivery. `fanoutCommittedEvent` enforces routing rules and requires an injected transaction to verify the committed event before inserting deduplicated deliveries.

Migration 009 adds the delivery table and ready index under forced RLS with **no runtime grants or policies**. This deliberately prevents use until a reviewed, tightly scoped service role and database adapter are implemented.

The in-memory tests exercise sequential protocol behavior only. Integration gates: verified server-owned registry, transactional SQL adapter, concurrent insert/replay tests, claim/fencing/retries per consumer, independent delivery receipts, revocation checks at dispatch, trusted credentials, webhook security and security review. The older one-event outbox worker cannot be reused unchanged for multiple consumers.

No production connection, Base44, Enforcer or Swift app changes.
