-- Trusted internal management role; must never be assigned to client-facing DB users.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_registry_manager') THEN
  CREATE ROLE halo_registry_manager NOLOGIN NOBYPASSRLS;
 END IF;
END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_registry_manager;
GRANT SELECT,INSERT,UPDATE ON halo_execution.integration_registrations TO halo_registry_manager;
GRANT SELECT,INSERT ON halo_execution.integration_registry_audit,halo_execution.integration_registry_receipts TO halo_registry_manager;
CREATE POLICY registry_management_scope ON halo_execution.integration_registrations TO halo_registry_manager
 USING (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''))
 WITH CHECK (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
CREATE POLICY registry_audit_management_scope ON halo_execution.integration_registry_audit TO halo_registry_manager
 USING (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''))
 WITH CHECK (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
CREATE POLICY registry_receipts_management_scope ON halo_execution.integration_registry_receipts TO halo_registry_manager
 USING (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''))
 WITH CHECK (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
