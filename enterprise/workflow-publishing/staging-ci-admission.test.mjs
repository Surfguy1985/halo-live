import test from "node:test";
import assert from "node:assert/strict";
import {assertCIStagingWorkflowConfiguration} from "./staging-ci-admission.mjs";

const sha="a".repeat(40);
const valid=()=>({
 CI:"true",GITHUB_ACTIONS:"true",GITHUB_REPOSITORY:"Surfguy1985/halo-live",
 GITHUB_REF:"refs/heads/codex/halo-enterprise-reconciliation-rc1",
 GITHUB_SHA:sha,HALO_EXPECTED_RELEASE_SHA:sha,HALO_DEPLOYMENT_ENV:"ci",
 HALO_WORKFLOW_PUBLISH_ENABLED:"true",HALO_WORKFLOW_DEPLOYMENT_APPROVED:"ephemeral-ci-only",
 HALO_WORKFLOW_EPHEMERAL_TEST_ONLY:"true",HALO_WORKFLOW_BIND_HOST:"127.0.0.1",
 HALO_WORKFLOW_PORT:"0",HALO_WORKFLOW_DATABASE_USER:"halo_workflow_runtime",
 HALO_IDENTITY_DATABASE_USER:"halo_identity_runtime",
 HALO_WORKFLOW_PUBLIC_URL:"https://workflow.staging.invalid/",
 HALO_WORKFLOW_AUTH_ISSUER:"https://identity.staging.invalid/ci",
 HALO_WORKFLOW_AUTH_AUDIENCE:"halo-staging-ci",
 HALO_WORKFLOW_DATABASE_URL:"postgresql://postgres:staging-ci-only@127.0.0.1:5432/halo_staging_ci?sslmode=disable",
 HALO_WORKFLOW_REDIS_URL:"redis://127.0.0.1:6379/0",
 HALO_PAYMENTS_ENABLED:"false",HALO_WEBHOOKS_ENABLED:"false",
 HALO_DISPATCH_ENABLED:"false",HALO_ENFORCER_ENABLED:"false",
 HALO_OUTBOUND_SIDE_EFFECTS:"disabled"
});
const rejected=override=>assert.throws(
 ()=>assertCIStagingWorkflowConfiguration({...valid(),...override}),
 {message:"HALO CI staging admission denied"}
);

test("admits only the exact disposable GitHub deployment boundary",()=>{
 assert.deepEqual(assertCIStagingWorkflowConfiguration(valid()),{
  environment:"ci",publicHost:"workflow.staging.invalid",
  issuerHost:"identity.staging.invalid",databaseName:"halo_staging_ci",
  bindHost:"127.0.0.1",releaseSHA:sha,
  workflowUser:"halo_workflow_runtime",identityUser:"halo_identity_runtime",
  requireTLS:false
 });
});
test("cannot admit production, staging, another repository or another SHA",()=>{
 rejected({GITHUB_ACTIONS:"false"});rejected({GITHUB_REPOSITORY:"other/repo"});
 rejected({GITHUB_REF:"refs/heads/main"});rejected({HALO_DEPLOYMENT_ENV:"staging"});
 rejected({HALO_EXPECTED_RELEASE_SHA:"b".repeat(40)});
});
test("rejects every enabled or ambiguous outbound side effect",()=>{
 for(const name of ["HALO_PAYMENTS_ENABLED","HALO_WEBHOOKS_ENABLED",
  "HALO_DISPATCH_ENABLED","HALO_ENFORCER_ENABLED"]) rejected({[name]:"true"});
 rejected({HALO_OUTBOUND_SIDE_EFFECTS:"allow"});
});
test("rejects non-loopback and connection-string override targets",()=>{
 for(const url of [
  "postgresql://postgres:staging-ci-only@db.example/halo_staging_ci?sslmode=disable",
  "postgresql://postgres:staging-ci-only@127.0.0.1:5432/halo_staging_ci?sslmode=disable&host=db.example",
  "postgresql://postgres:staging-ci-only@127.0.0.1:5432/halo_staging_ci?sslmode=disable&sslmode=verify-full",
  "postgresql://postgres:wrong@127.0.0.1:5432/halo_staging_ci?sslmode=disable"
 ]) rejected({HALO_WORKFLOW_DATABASE_URL:url});
 rejected({HALO_WORKFLOW_REDIS_URL:"redis://cache.example:6379/0"});
 rejected({HALO_WORKFLOW_PUBLIC_URL:"https://api.staging.halo.example"});
});
