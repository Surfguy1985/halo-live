import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresConsumerDeliveryStore} from "./postgres-consumer-delivery.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable halo_test DB required");
test("Postgres consumer queue: independent consumers, fencing, retry",{skip:!url},async()=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const file of ["005_work_item_execution.sql","006_outbox_delivery.sql","008_outbox_lease_token.sql","009_consumer_deliveries.sql","010_consumer_dispatcher.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+file,import.meta.url)),"utf8"));
  const eventID="a".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'assign')",[eventID]);
  for(const consumer of ["enforcer","accounting"])
   await pool.query("INSERT INTO halo_execution.consumer_deliveries(tenant_id,event_id,consumer_id) VALUES('tenant-a',$1,$2)",[eventID,consumer]);
  const store=new PostgresConsumerDeliveryStore(pool),now=Date.now();
  const [first,duplicate]=await Promise.all([
   store.claim({consumerID:"enforcer",workerID:"worker-a",now,leaseMs:30000}),
   store.claim({consumerID:"enforcer",workerID:"worker-b",now,leaseMs:30000})
  ]);
  assert.equal([first,duplicate].filter(Boolean).length,1);
  const entry=first||duplicate;const owner=first?"worker-a":"worker-b";
  const other=await store.claim({consumerID:"accounting",workerID:"account-worker",now,leaseMs:30000});
  assert.equal(other.consumerID,"accounting");
  const info={tenantID:"tenant-a",eventID,consumerID:"enforcer",workerID:owner,leaseToken:entry.leaseToken,now:now+100};
  assert.equal(await store.complete({...info,leaseToken:"wrong"}),false);
  await assert.rejects(()=>store.retry({...info,availableAt:Infinity,errorCode:"TIMEOUT"}),TypeError);
  await assert.rejects(()=>store.retry({...info,availableAt:-1,errorCode:"TIMEOUT"}),TypeError);
  assert.equal(await store.retry({...info,availableAt:now+2000,errorCode:"TIMEOUT"}),true);
  assert.equal(await store.claim({consumerID:"enforcer",workerID:"worker-c",now:now+300,leaseMs:30000}),null);
  // Fake future time cannot make an unavailable job claimable.
  assert.equal(await store.claim({consumerID:"enforcer",workerID:"worker-c",now:now+3600000,leaseMs:30000}),null);
  // Simulate elapsed retry interval on the disposable database, never caller time.
  await pool.query("UPDATE halo_execution.consumer_deliveries SET available_at=clock_timestamp()-interval '1 second' WHERE tenant_id='tenant-a' AND consumer_id='enforcer'");
  const retry=await store.claim({consumerID:"enforcer",workerID:"worker-c",now:now+2001,leaseMs:30000});
  assert.ok(retry);
  assert.equal(await store.complete({...info,now:now+2100}),false);
  assert.equal(await store.complete({tenantID:"tenant-a",eventID,consumerID:"enforcer",workerID:"worker-c",leaseToken:retry.leaseToken,now:now+2100}),true);
  assert.equal(await store.deadLetter({tenantID:"tenant-a",eventID,consumerID:"accounting",workerID:"account-worker",leaseToken:other.leaseToken,now:now+2200,errorCode:"REJECTED"}),true);
  const rows=await pool.query("SELECT consumer_id,status FROM halo_execution.consumer_deliveries ORDER BY consumer_id");
  assert.deepEqual(rows.rows,[{consumer_id:"accounting",status:"dead_letter"},{consumer_id:"enforcer",status:"delivered"}]);
 }finally{await pool.end();}
});
