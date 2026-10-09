import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresDeliveryOutcomeStore} from "./postgres-delivery-outcome.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable halo_test_* DB required");
test("delivery outcomes: acknowledged/rejected, stale leases, and tenant fencing",{skip:!url},async()=>{
 const {Pool}=await import("pg"),pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const f of ["005_work_item_execution.sql","006_outbox_delivery.sql","008_outbox_lease_token.sql","009_consumer_deliveries.sql","014_dispatch_permits.sql","016_delivery_reliability.sql","017_delivery_outcome.sql","018_delivery_outcome_writer.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+f,import.meta.url)),"utf8"));
  const store=new PostgresDeliveryOutcomeStore(pool);
  async function seed(n,tenant="tenant-a"){
   const eventID=String(n).repeat(64),permitID="00000000-0000-4000-8000-"+String(n).repeat(12),token="lease-"+n;
   await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,$2,$3,1,'approve')",[eventID,tenant,"job-"+n]);
   await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id,lease_owner,lease_token,lease_until) VALUES($1,$2,'accounting','worker-a',$3,clock_timestamp()+interval '1 hour')",[tenant,eventID,token]);
   await pool.query("INSERT INTO halo_execution.dispatch_permits(tenant_id,consumer_id,permit_id,event_id,registration_revision,expires_at,consumed_at,lease_token) VALUES($1,'accounting',$2,$3,4,clock_timestamp()+interval '1 hour',clock_timestamp(),$4)",[tenant,permitID,eventID,token]);
   return {tenantID:tenant,consumerID:"accounting",eventID,workerID:"worker-a",leaseToken:token,permitID,registrationRevision:4};
  }
  const ok=await seed("1"),bad=await seed("2"),stale=await seed("3"),other=await seed("4","tenant-b");
  assert.equal(await store.commitOutcome({...ok,tenantID:"tenant-b",outcome:{state:"acknowledged"}}),false);
  assert.equal(await store.commitOutcome({...other,tenantID:"tenant-a",outcome:{state:"acknowledged"}}),false);
  assert.equal(await store.commitOutcome({...ok,outcome:{state:"acknowledged"}}),true);
  assert.equal(await store.commitOutcome({...ok,outcome:{state:"acknowledged"}}),false);
  assert.equal(await store.commitOutcome({...bad,outcome:{state:"rejected"}}),true);
  await pool.query("UPDATE halo_execution.consumer_deliveries SET lease_until=clock_timestamp()-interval '1 second' WHERE tenant_id='tenant-a' AND event_id=$1",[stale.eventID]);
  assert.equal(await store.commitOutcome({...stale,outcome:{state:"acknowledged"}}),false);
  const r=await pool.query("SELECT event_id,status,outcome FROM halo_execution.consumer_deliveries WHERE tenant_id='tenant-a' ORDER BY event_id");
  assert.deepEqual(r.rows.map(x=>[x.status,x.outcome]),[["delivered","acknowledged"],["dead_letter","rejected"],["pending",null]]);
  const audit=await pool.query("SELECT count(*)::int AS n FROM halo_execution.delivery_outcome_audit");
  assert.equal(audit.rows[0].n,2);
 }finally{await pool.end();}
});
