-- Reconciliation state is separate from the original immutable delivery outcome.
ALTER TABLE halo_execution.consumer_deliveries
 ADD COLUMN reconciliation_revision bigint NOT NULL DEFAULT 0 CHECK(reconciliation_revision>=0),
 ADD COLUMN reconciliation_state text NOT NULL DEFAULT 'unreviewed'
  CHECK(reconciliation_state IN ('unreviewed','escalated','confirmed_delivered','confirmed_not_processed'));
CREATE TABLE halo_execution.delivery_reconciliation_audit(
 tenant_id text NOT NULL,event_id char(64) NOT NULL,consumer_id text NOT NULL,
 revision bigint NOT NULL,operator_id text NOT NULL,resolution text NOT NULL,
 verification_id text,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,event_id,consumer_id,revision)
);
REVOKE ALL ON halo_execution.delivery_reconciliation_audit FROM PUBLIC;
ALTER TABLE halo_execution.delivery_reconciliation_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.delivery_reconciliation_audit FORCE ROW LEVEL SECURITY;
-- No grants or policies. A reviewed internal resolution service is required.
