# Durable dispatch permits — draft gateway boundary

Proposed SQL table stores tenant/consumer-scoped single-use permits, event IDs, registration generations, expiries and revocation timestamps under forced row-level security. **No grants or policies permit access yet.** A pure gateway contract accepts only trusted store decisions; fixture tests cover replay, expiry and revision changes.

Security release blockers:
1. Implement PostgreSQL adapter that atomically consumes a permit only if the permit is unexpired/unconsumed, delivery lease is current, and authoritative registry enabled/revision match under appropriate locking.
2. Registration revocation must fence permits consistently within the same trusted database transaction boundary; external sends already started cannot be un-sent.
3. Enforce signed, authenticated service-to-service transport, trusted credentials, request timeouts, monitoring and consumer-side idempotency.
4. Execute SQL concurrency/revocation tests and pass CI. Never accept a permit ID, registration revision or time directly from an untrusted browser as authority.

No network delivery, deployment, Base44 or Enforcer mutation.
