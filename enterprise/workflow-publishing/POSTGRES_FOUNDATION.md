# Workflow publishing: PostgreSQL persistence foundation

**Status:** isolated migration proposal; no database, API, Base44 app or Enforcer integration has been changed.

## Apply only after a database/permission review

The SQL in `001_workflow_publishing.sql` creates tenant-scoped template identity rows, immutable revision snapshots, idempotency receipts, and an append-only-by-application audit table. It enables and forces RLS **without granting runtime policies**; ordinary database roles are denied by default. This is intentional, not a ready-to-run production API.

## Required transaction algorithm

1. Authenticate the session outside the request JSON, authorize `workflow:publish`, and resolve tenant/industry membership.
2. Validate typed block config, request size, all transition rules, and canonical request hash.
3. Begin a database transaction. Insert the `template_heads` identity row with `ON CONFLICT DO NOTHING` for first publication, then `SELECT ... FOR UPDATE` on that row. The initial industry must be checked, not silently changed.
4. Under the lock, check `publish_idempotency` for the key: return a matching stored response or reject a mismatched fingerprint.
5. Compare the locked revision to `expectedRevision`; on mismatch return conflict. Insert the next immutable revision.
6. Update the head using the expected revision fence, insert the idempotency receipt, then insert the audit row. Commit **all four changes together**. This ordering satisfies the audit foreign key to the receipt.
7. Generate timestamps and actor ID on the trusted server. Keep all DB connections tenant-bound with a reviewed authorization/RLS strategy. Do not let clients set trusted session scope using arbitrary SQL session variables.

## Important limitations

- SQL constraints do not validate workflow JSON semantics. The reference publisher is not yet connected to this migration.
- RLS policies, SQL privileges, a restricted non-owner service role, transactional adapter, migration runner, API authentication, and concurrency integration tests must be implemented before release.
- Restrict `UPDATE` / `DELETE` on revisions and audit at the database privilege level and add tamper-resistant audit export for regulated deployments.
- Never execute this migration against a live Base44/Enforcer database without a backup, rollback plan, and schema review.

## Acceptance tests before enabling API

Concurrent first publications; simultaneous duplicate keys; mismatched retry; stale revision; tenant/industry isolation; rollback after simulated audit failure; attempted revision mutation; unauthorized SQL role; restart/retry durability; strict per-block config validation. Run with an actual PostgreSQL database, not an in-memory mock.
