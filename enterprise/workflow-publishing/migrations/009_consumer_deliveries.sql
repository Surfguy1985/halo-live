-- Isolated per-consumer fanout foundation; DBA-owned migration.
CREATE TABLE halo_execution.consumer_deliveries (
 tenant_id text NOT NULL,
 event_id char(64) NOT NULL REFERENCES halo_execution.transition_outbox(event_id),
 consumer_id text NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','delivered','dead_letter')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts >= 0),
 available_at timestamptz NOT NULL DEFAULT now(),
 lease_owner text,
 lease_token text,
 lease_until timestamptz,
 delivered_at timestamptz,
 last_error_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,event_id,consumer_id),
 CHECK ((lease_owner IS NULL AND lease_token IS NULL AND lease_until IS NULL) OR
        (lease_owner IS NOT NULL AND lease_token IS NOT NULL AND lease_until IS NOT NULL))
);
CREATE INDEX consumer_deliveries_ready_idx ON halo_execution.consumer_deliveries(available_at,created_at)
 WHERE status='pending';
REVOKE ALL ON halo_execution.consumer_deliveries FROM PUBLIC;
ALTER TABLE halo_execution.consumer_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.consumer_deliveries FORCE ROW LEVEL SECURITY;
-- No default runtime grants or worker policies: fail closed pending dedicated
-- per-consumer worker identity and permission design.
