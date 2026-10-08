-- HALO isolated security phase, PostgreSQL 15+. Never execute against a live database without review.
-- A DBA provisions halo_workflow_executor as a NOLOGIN, NOBYPASSRLS role first.
-- Do NOT grant this role to public-facing users or arbitrary SQL clients.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor' AND NOT rolbypassrls)
 THEN RAISE EXCEPTION 'Provision halo_workflow_executor as NOBYPASSRLS before migration';
 END IF;
END $$;
REVOKE ALL ON SCHEMA halo_workflow FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA halo_workflow FROM PUBLIC;
GRANT USAGE ON SCHEMA halo_workflow TO halo_workflow_executor;
GRANT SELECT, INSERT, UPDATE ON halo_workflow.template_heads TO halo_workflow_executor;
GRANT SELECT, INSERT ON halo_workflow.template_revisions TO halo_workflow_executor;
GRANT SELECT, INSERT ON halo_workflow.publish_idempotency TO halo_workflow_executor;
GRANT SELECT, INSERT ON halo_workflow.publish_audit TO halo_workflow_executor;
GRANT USAGE ON SEQUENCE halo_workflow.publish_audit_audit_id_seq TO halo_workflow_executor;

-- Transaction-local session scope MUST originate from verified middleware.
-- Empty/missing scope denies access; direct DB users cannot be given executor membership.
CREATE POLICY tenant_heads_select ON halo_workflow.template_heads
 FOR SELECT TO halo_workflow_executor USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_heads_insert ON halo_workflow.template_heads
 FOR INSERT TO halo_workflow_executor WITH CHECK
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_heads_update ON halo_workflow.template_heads
 FOR UPDATE TO halo_workflow_executor USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''))
 WITH CHECK (tenant_id = nullif(current_setting('halo.tenant_id',true),''));

CREATE POLICY tenant_revisions_select ON halo_workflow.template_revisions
 FOR SELECT TO halo_workflow_executor USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_revisions_insert ON halo_workflow.template_revisions
 FOR INSERT TO halo_workflow_executor WITH CHECK
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_dedupe_select ON halo_workflow.publish_idempotency
 FOR SELECT TO halo_workflow_executor USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_dedupe_insert ON halo_workflow.publish_idempotency
 FOR INSERT TO halo_workflow_executor WITH CHECK
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_audit_select ON halo_workflow.publish_audit
 FOR SELECT TO halo_workflow_executor USING
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
CREATE POLICY tenant_audit_insert ON halo_workflow.publish_audit
 FOR INSERT TO halo_workflow_executor WITH CHECK
 (tenant_id = nullif(current_setting('halo.tenant_id',true),''));
COMMIT;
