# HALO uncertain-delivery reconciliation — draft

An authorized tenant-scoped operator may propose an audited resolution of a previously uncertain delivery: verified processed, verified not processed, or escalated. The decision contract requires a server-owned, event-bound verification result for factual confirmations. Escalation does not authorize retry. Confirmed non-processing still requires a separate human-approved retry flow with recipient-side idempotency.

Migration 019 records reconciliation revisions, status and a dedicated append-only audit. No privileges or runtime policies are granted. **No PostgreSQL reconciliation transaction adapter or external receipt verifier exists in this change.**

Prior to production: implement authenticated operator membership, atomic revision CAS and audit transaction, trusted recipient receipt lookup, limited retry approval, dual control for financial events, timeouts and security/CI testing. No live delivery or accounting integration.
