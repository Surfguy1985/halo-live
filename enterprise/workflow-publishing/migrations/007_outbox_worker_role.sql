-- Dedicated outbox delivery role. No tenant override or executor inherited grants.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_outbox_worker') THEN
  CREATE ROLE halo_outbox_worker NOLOGIN NOBYPASSRLS;
 END IF;
END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_outbox_worker;
GRANT SELECT,UPDATE ON halo_execution.transition_outbox TO halo_outbox_worker;
CREATE POLICY outbox_delivery_worker ON halo_execution.transition_outbox
 TO halo_outbox_worker USING (true) WITH CHECK (true);
-- Work-item and audit tables remain inaccessible to the worker.
