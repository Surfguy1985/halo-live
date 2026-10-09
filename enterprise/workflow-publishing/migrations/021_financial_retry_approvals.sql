-- A durable approval record, intentionally inaccessible to runtime callers.
CREATE TABLE halo_execution.financial_retry_approvals(
 tenant_id text NOT NULL,event_id char(64) NOT NULL,consumer_id text NOT NULL,
 reconciliation_revision bigint NOT NULL,
 requested_by text NOT NULL,approved_by text NOT NULL,verification_id text NOT NULL,
 state text NOT NULL DEFAULT 'approved' CHECK(state IN ('approved','consumed','revoked')),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,event_id,consumer_id,reconciliation_revision),
 CHECK(requested_by<>approved_by)
);
REVOKE ALL ON halo_execution.financial_retry_approvals FROM PUBLIC;
ALTER TABLE halo_execution.financial_retry_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.financial_retry_approvals FORCE ROW LEVEL SECURITY;
-- Deliberately no grants or RLS policies until reviewed internal DB service.
