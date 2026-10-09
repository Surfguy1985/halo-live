# Secure dispatch orchestration — draft, disabled by default

This composed pipeline checks an internal lease, performs a fresh registry authorization, consumes a single-use permit, retrieves server-held destination credentials, signs the event, and delegates to hardened transport. It is impossible to construct without explicit `enabled: true` and trusted adapters. No worker scheduler or production configuration enables it.

**Important blockers:** current permit consumption happens BEFORE network transmission, so failed/timeout sends need a new permit and receiver-side event-idempotency; it does not provide exactly-once delivery. Registry revocation can race after the authorization check; already-started requests cannot be recalled. Production still needs server-issued lease/permit linkage, current registration subscription enforcement within the permit DB transaction, a restricted secret vault, actual destination/SSRF security reviews, true total timeout controls, audit metrics, backpressure and red-team testing.

The tests use fake adapters; they do not establish production network safety or end-to-end database correctness. Do not connect live Enforcer, Base44 or other systems based on this PR alone.
