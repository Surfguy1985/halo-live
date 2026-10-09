# HALO workflow transition decision kernel — isolated v1

This pure, **non-persistent** engine answers whether a proposed transition is eligible for further server-side processing. It supports the starter linear flow:
`created -> assigned -> accepted -> in_progress -> evidence_pending -> review_pending -> approved -> closed`.

It checks session identity, tenant and industry scope, work item state and pinned template, optimistic revision, action role, assignee identity, approval separation of duties, and server-verified evidence references. Result contains a proposed next revision, **not** a committed state.

**Not yet built:** backend endpoint, durable work-item tables, locked transactional compare-and-swap, idempotency, audit + transactional outbox, evidence verifier, dynamic tenant-defined transitions, cancellation/rework branches, Enforcer/dispatch/payments. In particular, client-generated `serverVerified` is NOT authoritative; only a server-side verification adapter may construct this object.

Treat inputs as coming from verified backend middleware and authoritative DB reads, never from a mobile/browser request body. Production integration must tie this decision to transaction-bound loading and commit, enforce membership, and verify evidence independently.

This commit deliberately does not modify Base44, Enforcer, SwiftUI, default branch, or live HALO.
