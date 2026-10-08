-- HALO Workflow Publishing / PostgreSQL 15+ (isolated proposal, NOT auto-applied).
-- Migration runner must serialize deployments. Backend identity and tenant scope are mandatory.
BEGIN;

CREATE SCHEMA IF NOT EXISTS halo_workflow;

-- This identity row is locked BEFORE reading revisions. It also serializes
-- two competing first publishes of the same tenant/template.
CREATE TABLE halo_workflow.template_heads (
  tenant_id text NOT NULL CHECK (length(trim(tenant_id)) BETWEEN 1 AND 128),
  template_id text NOT NULL CHECK (length(trim(template_id)) BETWEEN 1 AND 128),
  industry_id text NOT NULL CHECK (length(trim(industry_id)) BETWEEN 1 AND 128),
  revision bigint NOT NULL DEFAULT 0 CHECK (revision >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, template_id)
);

-- Immutable publishing history; every published revision remains available.
CREATE TABLE halo_workflow.template_revisions (
  tenant_id text NOT NULL,
  template_id text NOT NULL,
  revision bigint NOT NULL CHECK (revision >= 1),
  template_version bigint NOT NULL CHECK (template_version >= 1),
  layout jsonb NOT NULL CHECK (jsonb_typeof(layout) = 'object'),
  layout_sha256 char(64) NOT NULL CHECK (layout_sha256 ~ '^[0-9a-f]{64}$'),
  published_by text NOT NULL CHECK (length(trim(published_by)) > 0),
  published_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, template_id, revision),
  FOREIGN KEY (tenant_id, template_id)
    REFERENCES halo_workflow.template_heads(tenant_id, template_id)
);

CREATE TABLE halo_workflow.publish_idempotency (
  tenant_id text NOT NULL,
  template_id text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_sha256 char(64) NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
  response jsonb NOT NULL CHECK (jsonb_typeof(response) = 'object'),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, template_id, idempotency_key),
  FOREIGN KEY (tenant_id, template_id)
    REFERENCES halo_workflow.template_heads(tenant_id, template_id)
);

CREATE TABLE halo_workflow.publish_audit (
  audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL,
  template_id text NOT NULL,
  revision bigint NOT NULL,
  actor_id text NOT NULL CHECK (length(trim(actor_id)) > 0),
  event_type text NOT NULL CHECK (event_type = 'workflow.template.published'),
  content_sha256 char(64) NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  idempotency_key text NOT NULL,
  correlation_id text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tenant_id, template_id, revision)
    REFERENCES halo_workflow.template_revisions(tenant_id, template_id, revision),
  FOREIGN KEY (tenant_id, template_id, idempotency_key)
    REFERENCES halo_workflow.publish_idempotency(tenant_id, template_id, idempotency_key)
);
CREATE INDEX publish_audit_tenant_time
  ON halo_workflow.publish_audit (tenant_id, occurred_at DESC, audit_id DESC);

-- Deny access to ordinary roles until a reviewed authentication/authorization
-- adapter is installed. Table owners and roles with BYPASSRLS are privileged:
-- application roles MUST NOT own these tables or have BYPASSRLS.
ALTER TABLE halo_workflow.template_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.template_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.publish_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.publish_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.template_heads FORCE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.template_revisions FORCE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.publish_idempotency FORCE ROW LEVEL SECURITY;
ALTER TABLE halo_workflow.publish_audit FORCE ROW LEVEL SECURITY;

COMMIT;
