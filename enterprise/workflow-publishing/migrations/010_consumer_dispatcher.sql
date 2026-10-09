-- Dedicated internal dispatcher grants. Never expose to client sessions.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_consumer_dispatcher') THEN
 CREATE ROLE halo_consumer_dispatcher NOLOGIN NOBYPASSRLS; END IF; END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_consumer_dispatcher;
GRANT SELECT,UPDATE ON halo_execution.consumer_deliveries TO halo_consumer_dispatcher;
CREATE POLICY consumer_dispatcher_access ON halo_execution.consumer_deliveries
 TO halo_consumer_dispatcher USING (true) WITH CHECK (true);
-- Event metadata is looked up only through the delivery row tenant identity.
GRANT SELECT ON halo_execution.transition_outbox TO halo_consumer_dispatcher;
CREATE POLICY consumer_dispatcher_event_read ON halo_execution.transition_outbox
 TO halo_consumer_dispatcher USING (true);
