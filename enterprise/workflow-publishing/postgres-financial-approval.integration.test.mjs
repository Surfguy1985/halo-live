import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresFinancialApprovalStore} from "./postgres-financial-approval.mjs";
const dbURL=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(dbURL&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(dbURL).pathname.slice(1)))
 throw Error("Only disposable halo_test_* databases allowed");
test("PostgreSQL dual approval: one stored proposal, no queue release",{skip:!dbURL},async()=>{
 const {Pool}=await import("pg"),pool=new Pool({connectionString:dbURL,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const f of ["005_work_item_execution.sql","006_outbox_delivery.sql","008_outbox_lease_token.sql","009_consumer_deliveries.sql","014_dispatch_permits.sql","016_delivery_reliability.sql","019_delivery_reconciliation.sql","021_financial_retry_approvals.sql","022_financial_approval_writer.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+f,import.meta.url)),"utf8"));
  const eventID="a".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'approve')",[eventID]);
  await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id,outcome,available_at) VALUES('tenant-a',$1,'accounting','uncertain','infinity')",[eventID]);
  const delivery={tenantID:"tenant-a",consumerID:"accounting",eventID,outcome:"uncertain",status:"pending",reconciliationRevision:0};
  const receipt={serverVerified:true,finding:"not_processed",tenantID:"tenant-a",consumerID:"accounting",eventID,verificationID:"verified-a",verifierID:"verifier-c"};
  const requester={authenticated:true,tenantID:"tenant-a",actorID:"requester-a",permissions:["financial_retry:request"]};
  const approver={authenticated:true,tenantID:"tenant-a",actorID:"approver-b",permissions:["financial_retry:approve"]};
  const service=new PostgresFinancialApprovalStore(pool);
  const args={delivery,receipt,requester,approver,expectedRevision:0};
  const outcomes=await Promise.allSettled([service.propose(args),service.propose(args)]);
  assert.equal(outcomes.filter(x=>x.status==="fulfilled").length,1);
  const count=await pool.query("SELECT count(*)::int AS n FROM halo_execution.financial_retry_approvals");
  assert.equal(count.rows[0].n,1);
  const row=await pool.query("SELECT status,outcome,available_at='infinity'::timestamptz AS held FROM halo_execution.consumer_deliveries");
  assert.deepEqual(row.rows[0],{status:"pending",outcome:"uncertain",held:true});
 }finally{await pool.end();}
});
