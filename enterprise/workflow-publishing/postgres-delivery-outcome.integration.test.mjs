import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresDeliveryOutcomeStore} from "./postgres-delivery-outcome.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable halo_test_* DB required");
test("PostgreSQL delivery receipt: lease fencing and uncertain reconciliation",{skip:!url},async()=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const f of ["005_work_item_execution.sql","006_outbox_delivery.sql","008_outbox_lease_token.sql","009_consumer_deliveries.sql","014_dispatch_permits.sql","016_delivery_reliability.sql","017_delivery_outcome.sql","018_delivery_outcome_writer.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+f,import.meta.url)),"utf8"));
  const eventID="a".repeat(64),permitID="00000000-0000-4000-8000-000000000001";
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'approve')",[eventID]);
  await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id,lease_owner,lease_token,lease_until) VALUES ('tenant-a',$1,'enforcer','worker-a','token-a',now()+interval '1 hour')",[eventID]);
  await pool.query("INSERT INTO halo_execution.dispatch_permits(tenant_id,consumer_id,permit_id,event_id,registration_revision,expires_at,consumed_at,lease_token) VALUES ('tenant-a','enforcer',$1,$2,3,now()+interval '1 hour',now(),'token-a')",[permitID,eventID]);
  const store=new PostgresDeliveryOutcomeStore(pool);
  const args={tenantID:"tenant-a",consumerID:"enforcer",eventID,workerID:"worker-a",leaseToken:"token-a",permitID,registrationRevision:3,outcome:{state:"uncertain"}};
  assert.equal(await store.commitOutcome({...args,leaseToken:"wrong"}),false);
  const races=await Promise.all([store.commitOutcome(args),store.commitOutcome(args)]);
  assert.deepEqual(races.sort(),[false,true]);
  const r=await pool.query("SELECT status,outcome,available_at='infinity'::timestamptz AS quarantined FROM halo_execution.consumer_deliveries WHERE tenant_id='tenant-a'");
  assert.deepEqual(r.rows[0],{status:"pending",outcome:"uncertain",quarantined:true});
  const audit=await pool.query("SELECT count(*)::int AS n FROM halo_execution.delivery_outcome_audit");
  assert.equal(audit.rows[0].n,1);
 }finally{await pool.end();}
});
