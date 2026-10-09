# HALO transaction protocol: work-item transition v1

Status: **isolated reference adapter; NOT a real durable database implementation, not deployed**.

`WorkflowTransitionService` accepts an internally verified session, a server-owned evidence verification object, and an injected transactional persistence adapter. It records a proposed workflow transition, audit, outbox intent and idempotency response in a single callback. It does not operate on Base44, Enforcer, Swift, or a live API.

## Required production store transaction contract

`store.transaction(tenantID, workItemID, fn)` must lock the tenant-scoped row and support:
- `getIdempotency(key)`: tenant/work-item scoped durable receipt
- `getLockedWorkItem()`: authoritative snapshot acquired with row lock
- `updateState({expectedRevision, revision, state})`: exactly-one-row compare-and-swap
- `appendAudit(event)`: immutable, tenant-scoped audit
- `appendOutbox(event)`: durable event, published only after COMMIT
- `saveIdempotency(key, receipt)`: unique within tenant/work-item

All six operations MUST use the same DB transaction and commit atomically. If any operation fails, all writes roll back. Race, deadlock/serialization-retry handling, RLS, and runtime credential isolation are not implemented in this step.

## Blocking before integration

PostgreSQL schema and adapter, database-backed concurrency tests, trusted authentication and evidence verifier, request-size and rate limits, worker membership checks, legal rework/cancellation paths, transactional outbox dispatcher and per-consumer dedupe. The memory tests are sequential protocol tests, NOT proof of concurrent durability or production security. No production routing.
