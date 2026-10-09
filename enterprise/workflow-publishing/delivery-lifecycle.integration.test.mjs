import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresOutboxLeaseStore} from "./postgres-outbox-lease.mjs";
import {PostgresConsumerDeliveryStore} from "./postgres-consumer-delivery.mjs";
import {PostgresPermitConsumptionStore} from "./postgres-permit-consumption.mjs";
import {PostgresDeliveryOutcomeStore} from "./postgres-delivery-outcome.mjs";
import {PostgresReconciliationService} from "./postgres-reconciliation.mjs";

const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw Error("Disposable halo_test_* database required");

test("HALO durable delivery lifecycle: outbox -> consumer -> permit -> uncertain -> escalation",{skip:!url},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:8});
 const eventID="d".repeat(64),permitID="00000000-0000-4000-8000-000000000044";
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const filename of [
   "005_work_item_execution.sql","006_outbox_delivery.sql",
   "007_outbox_worker_role.sql","008_outbox_lease_token.sql",
   "009_consumer_deliveries.sql","010_consumer_dispatcher.sql",
   "011_integration_registrations.sql","014_dispatch_permits.sql",
   "015_permit_gateway_role.sql","016_delivery_reliability.sql",
   "017_delivery_outcome.sql","018_delivery_outcome_writer.sql",
   "019_delivery_reconciliation.sql","020_reconciliation_writer.sql"
  ]) await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+filename,import.meta.url)),"utf8"));

  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'approve')",[eventID]);
  const outbox=new PostgresOutboxLeaseStore(pool);
  const claimed=await outbox.claim({workerID:"outbox-a",now:Date.now(),leaseMs:30000});
  assert.equal(claimed?.eventID,eventID);
  assert.equal(await outbox.complete({workerID:"outbox-a",eventID,leaseToken:claimed.leaseToken,now:Date.now()}),true);
  assert.equal(await outbox.complete({workerID:"outbox-a",eventID,leaseToken:claimed.leaseToken,now:Date.now()}),false);

  await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id) VALUES('tenant-a',$1,'accounting')",[eventID]);
  await pool.query(`INSERT INTO halo_execution.integration_registrations
    (tenant_id,consumer_id,enabled,event_types,allowed_actions,revision,updated_by)
    VALUES('tenant-a','accounting',true,'[]','[]',4,'owner-a')`);
  const queue=new PostgresConsumerDeliveryStore(pool);
  const work=await queue.claim({consumerID:"accounting",workerID:"consumer-a",now:Date.now(),leaseMs:30000});
  assert.equal(work?.eventID,eventID);
  assert.equal(await queue.claim({consumerID:"accounting",workerID:"consumer-b",now:Date.now()+3600000,leaseMs:30000}),null);

  await pool.query(`INSERT INTO halo_execution.dispatch_permits
    (tenant_id,consumer_id,permit_id,event_id,registration_revision,expires_at,lease_token)
    VALUES('tenant-a','accounting',$1,$2,4,clock_timestamp()+interval '1 hour',$3)`,
   [permitID,eventID,work.leaseToken]);
  const gateway=new PostgresPermitConsumptionStore(pool);
  const params={tenantID:"tenant-a",consumerID:"accounting",eventID,permitID,registrationRevision:4};
  assert.equal(await gateway.consumeIfAuthorized({...params,now:Date.now()}),true);
  assert.equal(await gateway.consumeIfAuthorized({...params,now:Date.now()}),false);

  const outcomes=new PostgresDeliveryOutcomeStore(pool);
  const outcomeParams={...params,workerID:"consumer-a",leaseToken:work.leaseToken,outcome:{state:"uncertain"}};
  assert.equal(await outcomes.commitOutcome(outcomeParams),true);
  assert.equal(await outcomes.commitOutcome(outcomeParams),false);
  const held=await pool.query(`SELECT status,outcome,available_at='infinity'::timestamptz AS held
    FROM halo_execution.consumer_deliveries WHERE tenant_id='tenant-a' AND event_id=$1`,[eventID]);
  assert.deepEqual(held.rows[0],{status:"pending",outcome:"uncertain",held:true});
  assert.equal(await queue.claim({consumerID:"accounting",workerID:"consumer-c",now:Date.now()+3600000,leaseMs:30000}),null);

  const resolution=new PostgresReconciliationService(pool);
  const decision=await resolution.resolve({
   session:{authenticated:true,tenantID:"tenant-a",actorID:"operator-a",permissions:["deliveries:reconcile"]},
   tenantID:"tenant-a",consumerID:"accounting",eventID,
   resolution:"escalate",expectedRevision:0
  });
  assert.equal(decision.nextRevision,1);
  assert.equal(decision.nextStatus,"pending");
  const stored=await pool.query("SELECT reconciliation_state FROM halo_execution.consumer_deliveries WHERE tenant_id=$1 AND event_id=$2",["tenant-a",eventID]);
  assert.equal(stored.rows[0].reconciliation_state,"escalated");
  const audit=await pool.query(`SELECT
   (SELECT count(*)::int FROM halo_execution.delivery_outcome_audit WHERE event_id=$1) AS outcomes,
   (SELECT count(*)::int FROM halo_execution.delivery_reconciliation_audit WHERE event_id=$1) AS reconciliations`,[eventID]);
  assert.deepEqual(audit.rows[0],{outcomes:1,reconciliations:1});
 }finally{await pool.end();}
});
