-- Draft durable dispatch permits. No runtime grants until gateway role review.
CREATE TABLE halo_execution.dispatch_permits (
 tenant_id text NOT NULL,consumer_id text NOT NULL,permit_id uuid NOT NULL,
 event_id char(64) NOT NULL,registration_revision bigint NOT NULL CHECK(registration_revision>0),
 expires_at timestamptz NOT NULL,consumed_at timestamptz,invalidated_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,consumer_id,permit_id)
);
CREATE INDEX dispatch_permits_active_idx ON halo_execution.dispatch_permits(tenant_id,consumer_id,expires_at)
 WHERE consumed_at IS NULL AND invalidated_at IS NULL;
REVOKE ALL ON halo_execution.dispatch_permits FROM PUBLIC;
ALTER TABLE halo_execution.dispatch_permits ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.dispatch_permits FORCE ROW LEVEL SECURITY;
-- No policy or role grants: fail closed by default.
