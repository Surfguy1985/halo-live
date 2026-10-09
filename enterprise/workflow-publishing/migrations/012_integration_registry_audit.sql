-- Additional durable audit/receipt tables. Access denied by default pending trusted adapter.
CREATE TABLE halo_execution.integration_registry_audit(
 tenant_id text NOT NULL,consumer_id text NOT NULL,revision bigint NOT NULL,
 actor_id text NOT NULL,action text NOT NULL,request_id text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,consumer_id,revision)
);
CREATE TABLE halo_execution.integration_registry_receipts(
 tenant_id text NOT NULL,consumer_id text NOT NULL,request_id text NOT NULL,
 expected_revision bigint NOT NULL,subscription jsonb NOT NULL,response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,consumer_id,request_id)
);
REVOKE ALL ON halo_execution.integration_registry_audit,halo_execution.integration_registry_receipts FROM PUBLIC;
ALTER TABLE halo_execution.integration_registry_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.integration_registry_audit FORCE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.integration_registry_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.integration_registry_receipts FORCE ROW LEVEL SECURITY;
-- No policies/grants until role-scoped management implementation is reviewed.
