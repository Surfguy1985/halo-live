-- Isolated work-item execution schema. DBA migration on disposable/test DB first.
CREATE SCHEMA IF NOT EXISTS halo_execution;
CREATE TABLE halo_execution.work_items(
 tenant_id text NOT NULL,work_item_id text NOT NULL,industry_id text NOT NULL,
 template_id text NOT NULL,template_version integer NOT NULL CHECK(template_version>0),
 assignee_id text,state text NOT NULL,revision bigint NOT NULL DEFAULT 0 CHECK(revision>=0),
 PRIMARY KEY(tenant_id,work_item_id),
 CHECK(state IN ('created','assigned','accepted','in_progress','evidence_pending','review_pending','approved','closed','cancelled'))
);
CREATE TABLE halo_execution.transition_receipts(
 tenant_id text NOT NULL,work_item_id text NOT NULL,idempotency_key text NOT NULL,
 fingerprint char(64) NOT NULL,response jsonb NOT NULL,
 PRIMARY KEY(tenant_id,work_item_id,idempotency_key)
);
CREATE TABLE halo_execution.transition_audit(
 tenant_id text NOT NULL,work_item_id text NOT NULL,revision bigint NOT NULL,
 actor_id text NOT NULL,action text NOT NULL,from_state text NOT NULL,to_state text NOT NULL,
 idempotency_key text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,work_item_id,revision)
);
CREATE TABLE halo_execution.transition_outbox(
 event_id char(64) PRIMARY KEY,tenant_id text NOT NULL,work_item_id text NOT NULL,
 revision bigint NOT NULL,action text NOT NULL,published_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,work_item_id,revision)
);
REVOKE ALL ON SCHEMA halo_execution FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA halo_execution FROM PUBLIC;
GRANT USAGE ON SCHEMA halo_execution TO halo_workflow_executor;
GRANT SELECT,UPDATE ON halo_execution.work_items TO halo_workflow_executor;
GRANT SELECT,INSERT ON halo_execution.transition_receipts TO halo_workflow_executor;
GRANT INSERT ON halo_execution.transition_audit TO halo_workflow_executor;
GRANT INSERT ON halo_execution.transition_outbox TO halo_workflow_executor;
-- All policies are deny-by-default without a trusted transaction-local tenant.
DO $$
DECLARE name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['work_items','transition_receipts','transition_audit','transition_outbox'] LOOP
  EXECUTE format('ALTER TABLE halo_execution.%I ENABLE ROW LEVEL SECURITY',name);
  EXECUTE format('ALTER TABLE halo_execution.%I FORCE ROW LEVEL SECURITY',name);
  EXECUTE format('CREATE POLICY tenant_only ON halo_execution.%I USING (tenant_id = NULLIF(current_setting(''halo.tenant_id'',true),'''')) WITH CHECK (tenant_id = NULLIF(current_setting(''halo.tenant_id'',true),''''))',name);
 END LOOP;
END $$;
