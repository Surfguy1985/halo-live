-- Tenant-scoped, SELECT-only role for workflow publish reconciliation.
-- This role can inspect durable receipts but cannot create templates, publish
-- revisions, append audit records, or modify any workflow row.
BEGIN;
DO $$ DECLARE reader_oid oid; BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_receipt_reader') THEN
  CREATE ROLE halo_workflow_receipt_reader NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB
   NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 END IF;
 SELECT oid INTO reader_oid FROM pg_roles
  WHERE rolname='halo_workflow_receipt_reader'
    AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
    AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
    AND NOT rolbypassrls;
 IF reader_oid IS NULL THEN
  RAISE EXCEPTION 'halo_workflow_receipt_reader has unsafe role attributes';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_auth_members WHERE member=reader_oid) OR
    EXISTS (SELECT 1 FROM pg_auth_members am JOIN pg_roles member_role ON member_role.oid=am.member
            WHERE am.roleid=reader_oid AND member_role.rolname<>'halo_workflow_runtime') THEN
  RAISE EXCEPTION 'halo_workflow_receipt_reader has unexpected role memberships';
 END IF;
END $$;
GRANT USAGE ON SCHEMA halo_workflow TO halo_workflow_receipt_reader;
GRANT SELECT ON halo_workflow.template_heads,halo_workflow.publish_idempotency
 TO halo_workflow_receipt_reader;
CREATE POLICY tenant_receipt_reader_heads ON halo_workflow.template_heads
 FOR SELECT TO halo_workflow_receipt_reader USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_receipt_reader_receipts ON halo_workflow.publish_idempotency
 FOR SELECT TO halo_workflow_receipt_reader USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
-- The public-facing login remains NOINHERIT and must explicitly SET LOCAL ROLE
-- inside a server-created transaction after trusted session verification.
GRANT halo_workflow_receipt_reader TO halo_workflow_runtime;
COMMIT;
