import test from "node:test";
import assert from "node:assert/strict";
import {assertCIRecoveryRehearsalConfiguration} from "./staging-ci-rehearsal-admission.mjs";

const sha="a".repeat(40);
const valid=()=>({
 CI:"true",GITHUB_ACTIONS:"true",GITHUB_REPOSITORY:"Surfguy1985/halo-live",
 GITHUB_REF:"refs/heads/codex/halo-enterprise-reconciliation-rc1",GITHUB_SHA:sha,
 HALO_EXPECTED_RELEASE_SHA:sha,HALO_DEPLOYMENT_ENV:"ci",HALO_WORKFLOW_PUBLISH_ENABLED:"true",
 HALO_WORKFLOW_DEPLOYMENT_APPROVED:"ephemeral-ci-only",HALO_WORKFLOW_EPHEMERAL_TEST_ONLY:"true",
 HALO_WORKFLOW_BIND_HOST:"127.0.0.1",HALO_WORKFLOW_PORT:"0",
 HALO_WORKFLOW_DATABASE_USER:"halo_workflow_runtime",HALO_IDENTITY_DATABASE_USER:"halo_identity_runtime",
 HALO_WORKFLOW_PUBLIC_URL:"https://workflow.staging.invalid/",
 HALO_WORKFLOW_AUTH_ISSUER:"https://identity.staging.invalid/ci",
 HALO_WORKFLOW_AUTH_AUDIENCE:"halo-staging-ci",
 HALO_WORKFLOW_DATABASE_URL:"postgresql://postgres:staging-ci-only@127.0.0.1:5432/halo_staging_ci?sslmode=disable",
 HALO_WORKFLOW_REDIS_URL:"redis://127.0.0.1:6379/0",HALO_PAYMENTS_ENABLED:"false",
 HALO_WEBHOOKS_ENABLED:"false",HALO_DISPATCH_ENABLED:"false",HALO_ENFORCER_ENABLED:"false",
 HALO_OUTBOUND_SIDE_EFFECTS:"disabled",HALO_REHEARSAL_APPROVED:"ephemeral-ci-backup-restore-rollback"
});

test("admits only the separately approved disposable recovery rehearsal",()=>{
 const result=assertCIRecoveryRehearsalConfiguration(valid());
 assert.equal(result.rehearsal,"backup-restore-rollback");
 assert.equal(result.releaseSHA,sha);
});

test("ordinary CI staging approval cannot authorize backup or restore",()=>{
 for(const approval of [undefined,"ephemeral-ci-only","production-backup"])
  assert.throws(()=>assertCIRecoveryRehearsalConfiguration({...valid(),HALO_REHEARSAL_APPROVED:approval}),
   /HALO CI recovery rehearsal admission denied/);
});
