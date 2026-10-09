# HALO Tenant-Aware Integration Routing v1

Pure policy filter between committed workflow events and future per-consumer delivery queues. Each registration is bound to an explicit tenant, allowed event type and action, with an enable flag. The router fails closed on malformed configurations and rejects duplicate matching registrations.

**Important:** this is NOT a durable receipt ledger or active dispatcher. The existing global outbox worker marks an event delivered once; it cannot safely support multiple consumers. Production requires transactional fan-out to per-consumer delivery rows with unique (tenant_id, event_id, consumer_id), atomic claim/ack/retry, revocation checks at delivery time, and consumer-held idempotency receipts before enabling network delivery. Authentication and allowlisted transport destinations, SSRF protection, secret rotation and signed payloads are not implemented.

No live Enforcer/API endpoints, credentials, network transport, Base44, native Swift or production changes.
