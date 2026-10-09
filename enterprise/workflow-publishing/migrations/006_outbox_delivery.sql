-- Isolated outbox delivery lease/receipt foundation.
ALTER TABLE halo_execution.transition_outbox
 ADD COLUMN attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 ADD COLUMN available_at timestamptz NOT NULL DEFAULT now(),
 ADD COLUMN lease_owner text,
 ADD COLUMN lease_until timestamptz,
 ADD COLUMN dead_letter_at timestamptz,
 ADD COLUMN last_error_code text;
CREATE INDEX transition_outbox_due_idx ON halo_execution.transition_outbox(available_at,created_at)
 WHERE published_at IS NULL AND dead_letter_at IS NULL;
CREATE TABLE halo_execution.delivery_receipts(
 consumer_id text NOT NULL,event_id char(64) NOT NULL,
 delivered_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(consumer_id,event_id)
);
REVOKE ALL ON halo_execution.delivery_receipts FROM PUBLIC;
GRANT SELECT,INSERT ON halo_execution.delivery_receipts TO halo_workflow_executor;
ALTER TABLE halo_execution.delivery_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.delivery_receipts FORCE ROW LEVEL SECURITY;
-- Delivery receipts are worker-only infrastructure, not end-user tenant data.
-- No executor policies added: deny all until a dedicated scoped worker role is built.
