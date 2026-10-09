# Atomic outcome receipt (draft)

This PostgreSQL adapter commits a consumer-delivery outcome only while the matching worker lease is current and the single-use permit has been consumed with the same tenant, event, consumer, lease token and registry revision. Outcome audit insertion occurs in the same transaction.

An uncertain network result is **quarantined** by making the delivery unavailable for automatic retry (`available_at='infinity'`); reconciliation must explicitly resolve it. The schema includes a privileged internal writer role, never a public route.

Remaining production blockers: prove permit issuance and registration scope, dispatch-time revocation, actor authentication, genuine TLS and recipient idempotency, integration migrations and CI, alerting/reconciliation, durable recipient receipts, and rework/cancellation policies. A global writer role is suitable only for a fully trusted internal process. No live integrations enabled.
