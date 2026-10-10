import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresPermitConsumptionStore} from "./postgres-permit-consumption.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable database required");
test("Postgres permit: concurrent one-time consumption, expiry, revocation",{skip:!url},async()=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOBYPASSRLS; END IF; END $$");
  for(const file of ["005_work_item_execution.sql","011_integration_registrations.sql","014_dispatch_permits.sql","015_permit_gateway_role.sql"])
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+file,import.meta.url)),"utf8"));
  await pool.query(`INSERT INTO halo_execution.integration_registrations(tenant_id,consumer_id,enabled,event_types,allowed_actions,revision,updated_by)
   VALUES('tenant-a','enforcer',true,'[]','[]',4,'owner-a')`);
  const permitID="00000000-0000-4000-8000-000000000001",eventID="a".repeat(64),now=Date.now();
  const seed=async(id,expiresAt=now+60_000)=>pool.query(`INSERT INTO halo_execution.dispatch_permits
   (tenant_id,consumer_id,permit_id,event_id,registration_revision,expires_at)
   VALUES('tenant-a','enforcer',$1,$2,4,to_timestamp($3/1000.0))`,[id,eventID,expiresAt]);
  await seed(permitID);
  const store=new PostgresPermitConsumptionStore(pool),input={tenantID:"tenant-a",consumerID:"enforcer",eventID,permitID,registrationRevision:4,now};
  const result=await Promise.all([store.consumeIfAuthorized(input),store.consumeIfAuthorized(input)]);
  assert.deepEqual(result.sort(),[false,true]);
  assert.equal(await store.consumeIfAuthorized(input),false);
  const expiredID="00000000-0000-4000-8000-000000000002";await seed(expiredID,now-1);
  assert.equal(await store.consumeIfAuthorized({...input,permitID:expiredID}),false);
  // Forged historical caller time cannot resurrect an expired permit.
  const forgedID="00000000-0000-4000-8000-000000000004";await seed(forgedID,now-1000);
  assert.equal(await store.consumeIfAuthorized({...input,permitID:forgedID,now:now-120_000}),false);
  const revokedID="00000000-0000-4000-8000-000000000003";await seed(revokedID);
  await pool.query("UPDATE halo_execution.integration_registrations SET enabled=false,revision=5 WHERE tenant_id='tenant-a' AND consumer_id='enforcer'");
  assert.equal(await store.consumeIfAuthorized({...input,permitID:revokedID}),false);
 }finally{await pool.end();}
});
