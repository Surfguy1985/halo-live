# Enterprise workflow publishing: reference contract

Status: **isolated reference implementation, not deployed**. Run `node --test enterprise/workflow-publishing/publisher.test.mjs` with Node 20+.

## Transactional persistence required

Each call to `store.transaction(tenantID, templateID, callback)` MUST run against the primary database in one serializable transaction (or equivalent atomic row lock). A test-only, single-threaded in-memory adapter is not sufficient. All functions on `tx` must use that **same** transaction:

- `getIdempotency(key)`: read an idempotency row unique on `(tenant_id, template_id, key)`.
- `getTemplate()`: lock the tenant-scoped template and retrieve current revision.
- `saveTemplate(layoutWithRevision)`: replace template state with optimistic revision precondition.
- `appendAudit(event)`: insert append-only, durable, tenant-scoped audit record.
- `saveIdempotency(key, result)`: atomically commit fingerprint and response.

Create a durable uniqueness fence for concurrent first publication, e.g. a locked template identity row before revision checks. Never allow two concurrent requests to publish revision 1. Idempotency row locks and conflict detection must also cover simultaneous matching and mismatching keys. On rollback, no state, audit or dedupe record may survive.

## Security requirements before route activation

- Authenticate sessions via trusted middleware. Do not accept tenant, actor, permissions or allowed industries from the request body.
- Authorize tenant access and publish permission on every request.
- Verify industry membership and that the resource belongs to the session tenant.
- Validate request size, JSON schema, block count, per-kind typed config, evidence requirements, allowed roles and all workflow transitions server-side. Current validator covers only layout shape, NOT all of these production requirements.
- Use a trusted audit actor ID, request correlation, timestamp, previous revision and content fingerprint.
- Apply rate limits, request bounds, deadline, observability and error redaction.
- Prove privacy isolation and conflicts under **concurrent database transactions**, not merely sequential unit tests.
- Keep existing Base44/Enforcer paths untouched until an API compatibility adapter and production security review are complete.

## Endpoint proposal

`POST /v1/workflow-templates/:templateID/publish`

Authenticated request with an idempotency header (e.g. `Idempotency-Key`) and body `{requestID, expectedRevision, layout}`. The route must require that the header key equals requestID. Domain service takes that verified key and trusted session separately. Responses: 200 published revision, 403 forbidden, 409 revision/idempotency conflict, 422 invalid schema. Backend generates authoritative timestamps and permissions.

## Next steps

1. Implement PostgreSQL adapter and migrations with transaction, RLS policy and uniqueness guarantees.
2. Add backend request/response schema and integration tests including concurrent publishing and rollback.
3. Reconcile Swift `Proposal` (UUID) with the HTTP header and JavaScript domain service.
4. Add API route behind feature flag and connect native draft editor only after end-to-end security tests.

## Server-owned layout contract v1 (isolated)

The publisher now validates every eight-kind block layout via `layout-contract.mjs`, before entering its database transaction. The contract rejects extra JSON keys, non-slug resource/role IDs, duplicate block IDs or ordering, duplicate visible roles, large titles and role arrays, and unknown per-kind configuration. It accepts up to 100 blocks and maintains the Swift-compatible string-valued `config` representation; all eight kinds have explicit, bounded fields. Existing empty configuration dictionaries remain valid.

Known optional configuration keys:
- assignment: `allowSelfAssign` ("true" or "false")
- location: `radiusMeters` (1–50000)
- checklist: `minChecks` (0–100)
- photoProof: `minPhotos` (1–20)
- pricing: `currencyCode` (three uppercase ASCII letters), `requireApprovedQuote` (boolean text)
- approval: `minApprovers` (1–10)
- messaging: `channel` (lowercase slug)
- closeout: `requireVerifiedEvidence` (boolean text)

This is a *schema and safe storage contract*, not approval logic, evidence validation, tenant authentication, permissions to execute, or an Enforcer integration. Introducing new configuration keys requires an explicit schema-versioned review across backend and native clients. The publishing service remains unmounted and feature-flagged off.
