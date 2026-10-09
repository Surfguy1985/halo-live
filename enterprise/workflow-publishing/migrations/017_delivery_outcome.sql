-- Acknowledged delivery is terminal; uncertain outcome is not auto-retried.
ALTER TABLE halo_execution.consumer_deliveries
 ADD CONSTRAINT consumer_delivery_outcome_consistency CHECK (
   outcome IS NULL OR
   (outcome='acknowledged' AND status='delivered') OR
   (outcome='rejected' AND status='dead_letter') OR
   (outcome='uncertain' AND status='pending')
 );
CREATE TABLE halo_execution.delivery_outcome_audit (
 tenant_id text NOT NULL, event_id char(64) NOT NULL,consumer_id text NOT NULL,
 lease_token text NOT NULL,outcome text NOT NULL CHECK(outcome IN ('acknowledged','rejected','uncertain')),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,event_id,consumer_id,lease_token)
);
REVOKE ALL ON halo_execution.delivery_outcome_audit FROM PUBLIC;
ALTER TABLE halo_execution.delivery_outcome_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.delivery_outcome_audit FORCE ROW LEVEL SECURITY;
-- No grants or policies; a reviewed internal role is necessary to use.
