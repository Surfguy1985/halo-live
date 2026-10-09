-- Isolated reference identity membership schema. DBA applies, never from browser/Swift.
BEGIN;
CREATE TABLE halo_workflow.identity_memberships (
 actor_id text PRIMARY KEY CHECK (length(trim(actor_id)) BETWEEN 1 AND 128),
 tenant_id text NOT NULL CHECK (length(trim(tenant_id)) BETWEEN 1 AND 128),
 active boolean NOT NULL DEFAULT false,
 industry_ids jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(industry_ids)='array'),
 permissions jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(permissions)='array'),
 revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX identity_memberships_tenant ON halo_workflow.identity_memberships(tenant_id);
ALTER TABLE halo_workflow.identity_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.identity_memberships FORCE ROW LEVEL SECURITY;
REVOKE ALL ON halo_workflow.identity_memberships FROM PUBLIC;
-- NO grants to halo_workflow_executor. This lookup must use a separate trusted
-- identity-service role with explicitly reviewed access, never client SQL.
COMMIT;
