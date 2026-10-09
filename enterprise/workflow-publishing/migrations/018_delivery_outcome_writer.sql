-- Trusted global internal writer, never exposed to client database sessions.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_delivery_outcome_writer') THEN
 CREATE ROLE halo_delivery_outcome_writer NOLOGIN NOBYPASSRLS; END IF; END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_delivery_outcome_writer;
GRANT SELECT,UPDATE ON halo_execution.consumer_deliveries TO halo_delivery_outcome_writer;
GRANT SELECT ON halo_execution.dispatch_permits TO halo_delivery_outcome_writer;
GRANT INSERT ON halo_execution.delivery_outcome_audit TO halo_delivery_outcome_writer;
CREATE POLICY outcome_delivery_write ON halo_execution.consumer_deliveries TO halo_delivery_outcome_writer USING(true) WITH CHECK(true);
CREATE POLICY outcome_permit_read ON halo_execution.dispatch_permits TO halo_delivery_outcome_writer USING(true);
CREATE POLICY outcome_audit_insert ON halo_execution.delivery_outcome_audit TO halo_delivery_outcome_writer WITH CHECK(true);
