import test from "node:test";
import assert from "node:assert/strict";
import {assertStagingWorkflowConfiguration} from "./staging-admission.mjs";

const valid = () => ({
  HALO_DEPLOYMENT_ENV: "staging",
  HALO_WORKFLOW_PUBLISH_ENABLED: "true",
  HALO_WORKFLOW_DEPLOYMENT_APPROVED: "staging-only",
  HALO_WORKFLOW_BIND_HOST: "127.0.0.1",
  HALO_WORKFLOW_DATABASE_USER: "halo_workflow_runtime",
  HALO_IDENTITY_DATABASE_USER: "halo_identity_runtime",
  HALO_WORKFLOW_PUBLIC_URL: "https://api.staging.halo.example",
  HALO_WORKFLOW_AUTH_ISSUER: "https://identity.example.test/issuer",
  HALO_WORKFLOW_AUTH_AUDIENCE: "halo-staging-workflow",
  HALO_WORKFLOW_DATABASE_URL:
    "postgresql://service:secret@db.example.test/halo_staging_workflow?sslmode=verify-full"
});
const rejected = overrides => assert.throws(
  () => assertStagingWorkflowConfiguration({...valid(), ...overrides}),
  {message: "HALO workflow staging admission denied"}
);

test("valid staging admission returns only non-secret metadata", () => {
  const result = assertStagingWorkflowConfiguration(valid());
  assert.deepEqual(result, {
    environment: "staging", publicHost: "api.staging.halo.example",
    issuerHost: "identity.example.test", databaseName: "halo_staging_workflow",
    bindHost: "127.0.0.1",workflowUser:"halo_workflow_runtime",
    identityUser:"halo_identity_runtime",requireTLS:true
  });
  assert.ok(Object.isFrozen(result));
  assert.doesNotMatch(JSON.stringify(result), /secret|postgresql:/);
});
test("publishing remains off without explicit staging environment and approval", () => {
  rejected({HALO_DEPLOYMENT_ENV: "production"});
  rejected({HALO_DEPLOYMENT_ENV: undefined});
  rejected({HALO_WORKFLOW_PUBLISH_ENABLED: "false"});
  rejected({HALO_WORKFLOW_PUBLISH_ENABLED: undefined});
  rejected({HALO_WORKFLOW_DEPLOYMENT_APPROVED: "production"});
  rejected({HALO_WORKFLOW_DEPLOYMENT_APPROVED: undefined});
  rejected({HALO_WORKFLOW_DATABASE_USER: "postgres"});
  rejected({HALO_IDENTITY_DATABASE_USER: "postgres"});
});
test("requires loopback-only Node bind behind staging TLS termination", () => {
  rejected({HALO_WORKFLOW_BIND_HOST: "0.0.0.0"});
  rejected({HALO_WORKFLOW_BIND_HOST: "::"});
  rejected({HALO_WORKFLOW_BIND_HOST: undefined});
});
test("rejects production, local, HTTP and credential-bearing public URLs", () => {
  for(const url of [
    "https://api.halo.example", "http://api.staging.halo.example",
    "https://127.0.0.1", "https://localhost",
    "https://user:pass@api.staging.halo.example",
    "https://api.staging.halo.example/other",
    "https://api.staging.halo.example?enabled=true",
    "https://api.staging.halo.example#fragment",
    "https://staging-evil.example"
  ]) rejected({HALO_WORKFLOW_PUBLIC_URL:url});
});
test("issuer must be HTTPS and audience explicitly staging-scoped", () => {
  rejected({HALO_WORKFLOW_AUTH_ISSUER: "http://identity.example.test"});
  rejected({HALO_WORKFLOW_AUTH_ISSUER: "https://127.0.0.1"});
  rejected({HALO_WORKFLOW_AUTH_ISSUER: "https://user:secret@identity.example.test"});
  rejected({HALO_WORKFLOW_AUTH_AUDIENCE: "halo-production-workflow"});
  rejected({HALO_WORKFLOW_AUTH_AUDIENCE: ""});
});
test("database must be staging-named and certificate-verified", () => {
  for(const url of [
    "postgresql://user:secret@db.example.test/halo_production?sslmode=verify-full",
    "postgresql://user:secret@db.example.test/halo_staging_workflow?sslmode=require",
    "postgresql://user:secret@db.example.test/halo_staging_workflow",
    "postgresql://user:secret@localhost/halo_staging_workflow?sslmode=verify-full",
    "postgresql://user:secret@127.0.0.1/halo_staging_workflow?sslmode=verify-full",
    "postgresql://user:secret@db.example.test/halo_staging_workflow?sslmode=verify-full&options=-c%20search_path%3Dpublic",
    "postgresql://user:secret@db.example.test/halo_staging_workflow?sslmode=verify-full&sslmode=disable",
    "postgresql://user:secret@db.example.test/halo_staging_workflow?sslmode=verify-full&host=127.0.0.1"
  ]) rejected({HALO_WORKFLOW_DATABASE_URL:url});
});
