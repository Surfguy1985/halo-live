-- Isolated registry metadata; no credentials or endpoint URLs persisted.
CREATE TABLE halo_execution.integration_registrations(
 tenant_id text NOT NULL,consumer_id text NOT NULL,
 enabled boolean NOT NULL DEFAULT false,
 event_types jsonb NOT NULL DEFAULT '[]'::jsonb,
 allowed_actions jsonb NOT NULL DEFAULT '[]'::jsonb,
 revision bigint NOT NULL DEFAULT 0 CHECK(revision>=0),
 updated_by text NOT NULL,updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,consumer_id),
 CHECK(jsonb_typeof(event_types)='array' AND jsonb_typeof(allowed_actions)='array')
);
REVOKE ALL ON halo_execution.integration_registrations FROM PUBLIC;
ALTER TABLE halo_execution.integration_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_execution.integration_registrations FORCE ROW LEVEL SECURITY;
-- Deliberately no runtime grants or tenant policies until authenticated
-- management endpoint, audit, optimistic revision CAS and revocation checks exist.
