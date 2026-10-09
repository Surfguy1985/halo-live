# Transactional outbox delivery — v1 isolated contract

This adds a pure one-event-at-a-time worker with a persistence interface for leasing, completion, retry and dead lettering. The SQL migration adds metadata, due index, and a deny-all delivery receipt table. **No PostgreSQL lease implementation, endpoint, webhooks, or Enforcer connector is activated.**

Required adapter semantics: `claim` atomically selects due unleased items via SKIP LOCKED, increments attempts, sets a random lease token and expiry, and returns a single event. `complete`, `retry` and `deadLetter` must compare the exact lease token, worker identity and unexpired lease; stale workers cannot finalize. Delivery receipts require tenant/consumer ownership authorization and exactly-once *effect* must be enforced by consumers using `consumerID + eventID`, not assumed from the queue.

Retries are deterministic exponential backoff with a one-hour cap and bounded attempts. Real deployment requires jitter, timeouts, circuit breakers, metrics, poison payload quarantine, service-role permissions, migration review, retention, event schema signatures and a fully authenticated Enforcer integration. **Do not run this migration against production before security review.**
