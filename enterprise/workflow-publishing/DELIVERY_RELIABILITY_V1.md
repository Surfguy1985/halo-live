# Delivery reliability — isolated v1

The pure protocol binds tenant, consumer, event and worker lease token to a permit. It distinguishes acknowledgment, permanent HTTP rejection, and **uncertain** outcomes. A timeout or server error is uncertain because the remote business action may already have occurred. Results must be committed through a durable lease-fenced adapter.

The schema adds lease binding and outcome metadata only. There is deliberately no automatic retry policy for uncertain outcomes, because that could duplicate an invoice, payment or dispatch. The receiving service must enforce event idempotency; operators need reconciliation for unknown outcomes.

Remaining release gates: atomic PostgreSQL lease+permit+registration verification; transactional delivery receipt/outcome CAS; trusted server identity; recipient idempotency; timeout and cancellation policy; CI; security review. No live network workers or integration activation.
