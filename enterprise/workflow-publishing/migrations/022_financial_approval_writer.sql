-- Internal-only approval writer, not available to end-user sessions.
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_financial_approval_writer') THEN
  CREATE ROLE halo_financial_approval_writer NOLOGIN NOBYPASSRLS;
 END IF;
END $$;
GRANT USAGE ON SCHEMA halo_execution TO halo_financial_approval_writer;
GRANT SELECT ON halo_execution.consumer_deliveries TO halo_financial_approval_writer;
GRANT SELECT,INSERT ON halo_execution.financial_retry_approvals TO halo_financial_approval_writer;
CREATE POLICY financial_approval_delivery_read ON halo_execution.consumer_deliveries
 TO halo_financial_approval_writer
 USING(tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
CREATE POLICY financial_approval_insert ON halo_execution.financial_retry_approvals
 TO halo_financial_approval_writer
 USING(tenant_id=NULLIF(current_setting('halo.tenant_id',true),''))
 WITH CHECK(tenant_id=NULLIF(current_setting('halo.tenant_id',true),''));
-- Revocation and consumption require a separate, reviewed service.
