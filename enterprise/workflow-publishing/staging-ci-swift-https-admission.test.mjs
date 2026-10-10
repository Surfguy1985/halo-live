import test from "node:test";
import assert from "node:assert/strict";
import {assertCIStagingSwiftHTTPSConfiguration} from "./staging-ci-swift-https-admission.mjs";

const valid={
 CI:"true",GITHUB_ACTIONS:"true",GITHUB_REPOSITORY:"Surfguy1985/halo-live",
 GITHUB_REF:"refs/heads/codex/halo-enterprise-reconciliation-rc1",
 GITHUB_SHA:"a".repeat(40),HALO_EXPECTED_RELEASE_SHA:"a".repeat(40),
 HALO_DEPLOYMENT_ENV:"ci",HALO_WORKFLOW_PUBLISH_ENABLED:"true",
 HALO_WORKFLOW_DEPLOYMENT_APPROVED:"ephemeral-ci-only",HALO_WORKFLOW_EPHEMERAL_TEST_ONLY:"true",
 HALO_WORKFLOW_BIND_HOST:"127.0.0.1",HALO_WORKFLOW_PORT:"0",
 HALO_WORKFLOW_DATABASE_USER:"halo_workflow_runtime",HALO_IDENTITY_DATABASE_USER:"halo_identity_runtime",
 HALO_PAYMENTS_ENABLED:"false",HALO_WEBHOOKS_ENABLED:"false",HALO_DISPATCH_ENABLED:"false",
 HALO_ENFORCER_ENABLED:"false",HALO_OUTBOUND_SIDE_EFFECTS:"disabled",
 HALO_WORKFLOW_PUBLIC_URL:"https://workflow.staging.invalid/",
 HALO_WORKFLOW_AUTH_ISSUER:"https://identity.staging.invalid/ci",
 HALO_WORKFLOW_AUTH_AUDIENCE:"halo-staging-ci",
 HALO_WORKFLOW_DATABASE_URL:"postgresql://postgres:staging-ci-only@127.0.0.1:5432/halo_staging_ci?sslmode=disable",
 HALO_WORKFLOW_REDIS_URL:"redis://127.0.0.1:6379/0",
 HALO_SWIFT_HTTPS_SIGNOFF_APPROVED:"ephemeral-ci-https-only",
 HALO_SWIFT_STAGING_HOST:"workflow.staging.invalid",
 HALO_SWIFT_SIGNOFF_EXECUTABLE:"/tmp/halo-swift-signoff",
 HALO_SWIFT_TLS_CERTIFICATE:"/tmp/halo-staging.crt",
 HALO_SWIFT_TLS_PRIVATE_KEY:"/tmp/halo-staging.key"
};

test("admits only the one-purpose Swift HTTPS signoff boundary",()=>{
 const result=assertCIStagingSwiftHTTPSConfiguration(valid);
 assert.equal(result.releaseSHA,valid.GITHUB_SHA);
 assert.equal(result.publicHost,"workflow.staging.invalid");
 assert.equal(result.swiftHTTPS,true);
});

test("inherits exact-SHA and disabled-side-effect admission",()=>{
 for(const mutation of [
  {HALO_EXPECTED_RELEASE_SHA:"b".repeat(40)},
  {HALO_PAYMENTS_ENABLED:"true"},
  {HALO_OUTBOUND_SIDE_EFFECTS:"enabled"},
  {GITHUB_REF:"refs/heads/main"}
 ]) assert.throws(()=>assertCIStagingSwiftHTTPSConfiguration({...valid,...mutation}),
  /HALO CI staging admission denied/);
});

test("rejects another host, approval, or non-absolute local artifact",()=>{
 for(const mutation of [
  {HALO_SWIFT_HTTPS_SIGNOFF_APPROVED:"production"},
  {HALO_SWIFT_STAGING_HOST:"workflow.example.com"},
  {HALO_SWIFT_SIGNOFF_EXECUTABLE:"./halo-swift-signoff"},
  {HALO_SWIFT_TLS_CERTIFICATE:""},
  {HALO_SWIFT_TLS_PRIVATE_KEY:"relative.key"}
 ]) assert.throws(()=>assertCIStagingSwiftHTTPSConfiguration({...valid,...mutation}),
  /HALO CI Swift HTTPS signoff admission denied/);
});
