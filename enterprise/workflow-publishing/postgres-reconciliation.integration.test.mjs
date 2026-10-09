import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresReconciliationService} from "./postgres-reconciliation.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable halo_test DB required");
test("Postgres reconciliation: concurrent CAS, immutable audit, tenant isolation",{skip:!url},async()=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const f of ["005_work_item_execution.sql","006_outbox_delivery.sql","008_outbox_lease_token.sql","009_consumer_deliveries.sql","014_dispatch_permits.sql","016_delivery_reliability.sql","019_delivery_reconciliation.sql","020_reconciliation_writer.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+f,import.meta.url)),"utf8"));
  const eventID="a".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'approve')",[eventID]);
  await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id,outcome,available_at) VALUES('tenant-a',$1,'accounting','uncertain','infinity')",[eventID]);
  const svc=new PostgresReconciliationService(pool);
  const session={authenticated:true,tenantID:"tenant-a",actorID:"operator-a",permissions:["deliveries:reconcile"]};
  const evidence={serverVerified:true,tenantID:"tenant-a",consumerID:"accounting",eventID,verificationID:"proof-a",finding:"processed"};
  const args={session,tenantID:"tenant-a",consumerID:"accounting",eventID,resolution:"confirmed_delivered",expectedRevision:0,evidence};
  const outcome=await Promise.allSettled([svc.resolve(args),svc.resolve(args)]);
  assert.equal(outcome.filter(x=>x.status==="fulfilled").length,1);
  const stored=await pool.query("SELECT status,outcome,reconciliation_revision,delivered_at FROM halo_execution.consumer_deliveries WHERE tenant_id='tenant-a'");
  assert.equal(stored.rows[0].status,"delivered");
  assert.ok(stored.rows[0].delivered_at instanceof Date,"confirmed delivery must have completion timestamp");
  assert.equal(Number(stored.rows[0].reconciliation_revision),1);
  const audit=await pool.query("SELECT count(*)::int n FROM halo_execution.delivery_reconciliation_audit");
  assert.equal(audit.rows[0].n,1);
  await assert.rejects(()=>svc.resolve({...args,session:{...session,tenantID:"tenant-b"}}));
  const c=await pool.connect();
  try{
   await c.query("BEGIN");await c.query("SET LOCAL ROLE halo_reconciliation_writer");
   assert.equal((await c.query("SELECT count(*)::int n FROM halo_execution.consumer_deliveries")).rows[0].n,0);
   await c.query("ROLLBACK");
  }finally{c.release();}
 }finally{await pool.end();}
});
