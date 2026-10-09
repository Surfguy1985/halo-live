import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {randomUUID} from "node:crypto";
import {PostgresOutboxLeaseStore} from "./postgres-outbox-lease.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("test database required");
test("real PostgreSQL: competing workers, fencing and retries",{skip:!url},async()=>{
 const {Pool}=await import("pg"),pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const file of ["005_work_item_execution.sql","006_outbox_delivery.sql","007_outbox_worker_role.sql","008_outbox_lease_token.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+file,import.meta.url)),"utf8"));
  const eventID="a".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-a',1,'assign')",[eventID]);
  const db=new PostgresOutboxLeaseStore(pool);const now=Date.now();
  const [a,b]=await Promise.all([db.claim({workerID:"worker-a",now,leaseMs:30000}),db.claim({workerID:"worker-b",now,leaseMs:30000})]);
  assert.equal([a,b].filter(Boolean).length,1);
  const claimed=a||b;const owner=a?"worker-a":"worker-b";
  await assert.rejects(()=>db.retry({workerID:owner,eventID,leaseToken:claimed.leaseToken,errorCode:"TIMEOUT"}),TypeError);
  await assert.rejects(()=>db.retry({workerID:owner,eventID,leaseToken:claimed.leaseToken,availableAt:Infinity,errorCode:"TIMEOUT"}),TypeError);
  await assert.rejects(()=>db.deadLetter({workerID:owner,eventID,leaseToken:claimed.leaseToken}),TypeError);
  assert.equal(await db.complete({workerID:"other",eventID,leaseToken:claimed.leaseToken,now:now+100}),false);
  assert.equal(await db.complete({workerID:owner,eventID,leaseToken:"wrong",now:now+100}),false);
  assert.equal(await db.complete({workerID:owner,eventID,leaseToken:claimed.leaseToken,now:now+100}),true);
  assert.equal(await db.complete({workerID:owner,eventID,leaseToken:claimed.leaseToken,now:now+100}),false);
  assert.equal(await db.claim({workerID:"worker-c",now:now+200,leaseMs:30000}),null);
  const futureID="b".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action,available_at) VALUES($1,'tenant-a','job-b',1,'assign',clock_timestamp()+interval '10 minutes')",[futureID]);
  assert.equal(await db.claim({workerID:"worker-c",now:now+3600000,leaseMs:30000}),null);
  const expiredID="c".repeat(64);
  await pool.query("INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,'tenant-a','job-c',1,'assign')",[expiredID]);
  const expired=await db.claim({workerID:"worker-c",now:now,leaseMs:30000});
  await pool.query("UPDATE halo_execution.transition_outbox SET lease_until=clock_timestamp()-interval '1 second' WHERE event_id=$1",[expiredID]);
  assert.equal(await db.complete({workerID:"worker-c",eventID:expiredID,leaseToken:expired.leaseToken,now:now-3600000}),false);
 }finally{await pool.end();}
});
