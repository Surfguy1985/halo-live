-- Internal-only reconciliation worker role; NEVER expose arbitrary SQL to tenants.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_reconciliation_writer') THEN
 CREATE ROLE halo_reconciliation_writer NOLOGIN NOBYPASSRLS; END IF; END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_reconciliation_writer;
GRANT SELECT,UPDATE ON halo_execution.consumer_deliveries TO halo_reconciliation_writer;
GRANT INSERT ON halo_execution.delivery_reconciliation_audit TO halo_reconciliation_writer;
CREATE POLICY reconciliation_delivery_rw ON halo_execution.consumer_deliveries TO halo_reconciliation_writer
 USING (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''))
 WITH CHECK (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
CREATE POLICY reconciliation_audit_insert ON halo_execution.delivery_reconciliation_audit TO halo_reconciliation_writer
 WITH CHECK (tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
