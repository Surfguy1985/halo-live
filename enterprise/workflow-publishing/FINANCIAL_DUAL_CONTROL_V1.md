# Financial two-person retry control (isolated v1)

A financial retry proposal requires: the previously uncertain delivery, matching independently verified **not processed** receipt, different authorized requester and approver, separate verifier identity, exact tenant/event/consumer binding, and current revision.

The decision is only **eligible for a separately approved, transactionally committed retry**. It never releases a queue, sends a financial action, or retries automatically. Migration 021 holds durable approval metadata under deny-all RLS.

Important release blockers: construct verification results exclusively from a trusted recipient receipt-verification service (a caller-provided serverVerified flag is NOT sufficient); strict actor membership/permission verification; cryptographically provable and fresh evidence; transactional state changes and single-use approval CAS; an operational risk policy for multi-actor collusion; signed transport with recipient-side idempotency; full CI and security review. No production integration.
