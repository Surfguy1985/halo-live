import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresIntegrationRegistryStore} from "./postgres-integration-registry.mjs";
import {IntegrationManagementService} from "./integration-management.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable database required");
test("Postgres registry: CAS races, audit, replay, tenant RLS",{skip:!url},async()=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  for(const file of ["005_work_item_execution.sql","011_integration_registrations.sql","012_integration_registry_audit.sql","013_registry_manager.sql"]){
   if(file==="005_work_item_execution.sql")await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOBYPASSRLS; END IF; END $$");
   await pool.query(await readFile(fileURLToPath(new URL("./migrations/"+file,import.meta.url)),"utf8"));
  }
  const svc=new IntegrationManagementService(new PostgresIntegrationRegistryStore(pool));
  const input=(tenant,requestID)=>({session:{authenticated:true,tenantID:tenant,actorID:"owner-a",permissions:["integrations:manage"]},tenantID:tenant,consumerID:"enforcer",expectedRevision:0,requestID,
   subscription:{enabled:true,eventTypes:["workflow.work_item.transitioned"],allowedActions:["approve"]}});
  const results=await Promise.allSettled([svc.update(input("tenant-a","one")),svc.update(input("tenant-a","two"))]);
  assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
  const winner=results.find(x=>x.status==="fulfilled").value;
  assert.equal(winner.revision,1);
  const winKey=results[0].status==="fulfilled"?"one":"two";
  assert.equal((await svc.update(input("tenant-a",winKey))).revision,1);
  assert.equal((await svc.update(input("tenant-b","one"))).revision,1);
  const audits=await pool.query("SELECT tenant_id,count(*)::int n FROM halo_execution.integration_registry_audit GROUP BY tenant_id ORDER BY tenant_id");
  assert.deepEqual(audits.rows.map(x=>[x.tenant_id,x.n]),[["tenant-a",1],["tenant-b",1]]);
  const c=await pool.connect();
  try{
   await c.query("BEGIN");await c.query("SET LOCAL ROLE halo_registry_manager");
   assert.equal((await c.query("SELECT count(*)::int n FROM halo_execution.integration_registrations")).rows[0].n,0);
   await c.query("ROLLBACK");
  }finally{c.release();}
 }finally{await pool.end();}
});
