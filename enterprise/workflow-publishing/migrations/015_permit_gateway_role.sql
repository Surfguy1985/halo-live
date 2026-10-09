-- Dedicated restricted role only for trusted internal permit gateway.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_permit_gateway') THEN
 CREATE ROLE halo_permit_gateway NOLOGIN NOBYPASSRLS; END IF; END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_permit_gateway;
GRANT SELECT,UPDATE ON halo_execution.dispatch_permits TO halo_permit_gateway;
GRANT SELECT ON halo_execution.integration_registrations TO halo_permit_gateway;
CREATE POLICY permit_gateway_access ON halo_execution.dispatch_permits TO halo_permit_gateway
 USING (true) WITH CHECK (true);
CREATE POLICY permit_gateway_registration_read ON halo_execution.integration_registrations
 TO halo_permit_gateway USING (true);
-- Global role reserved for internal gateway; no end-user sessions.
