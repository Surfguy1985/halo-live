import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresExecutionStore} from "./postgres-execution-store.mjs";
import {WorkflowTransitionService} from "./transition-service.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))throw Error("Disposable halo_test_* database required");
test("Postgres execution: concurrent CAS, replay, tenant isolation, audit rollback",{skip:!url},async t=>{
 const {Pool}=await import("pg");const pool=new Pool({connectionString:url,max:8});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  await pool.query(await readFile(fileURLToPath(new URL("./migrations/005_work_item_execution.sql",import.meta.url)),"utf8"));
  const seed=(tenant,id="job-a")=>pool.query(
   "INSERT INTO halo_execution.work_items(tenant_id,work_item_id,industry_id,template_id,template_version,assignee_id,state) VALUES($1,$2,'construction','dispatch',1,'crew-a','created')",[tenant,id]);
  await seed("tenant-a");await seed("tenant-b");
  const service=new WorkflowTransitionService(new PostgresExecutionStore(pool));
  const input=(tenant,key)=>({session:{authenticated:true,tenantID:tenant,actorID:"manager-a",roles:["manager"],industryIDs:["construction"]},workItemID:"job-a",action:"assign",expectedRevision:0,idempotencyKey:key});
  await t.test("at most one distinct-key concurrent transition commits",async()=>{
   const results=await Promise.allSettled([service.execute(input("tenant-a","one")),service.execute(input("tenant-a","two"))]);
   assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
   const count=await pool.query("SELECT count(*)::int AS n FROM halo_execution.transition_audit WHERE tenant_id='tenant-a'");
   assert.equal(count.rows[0].n,1);
  });
  await t.test("committed key retries with no second audit or outbox",async()=>{
   const key=(await pool.query("SELECT idempotency_key FROM halo_execution.transition_receipts WHERE tenant_id='tenant-a'")).rows[0].idempotency_key;
   const returned=await service.execute(input("tenant-a",key));
   assert.equal(returned.revision,1);
   const count=await pool.query("SELECT count(*)::int AS n FROM halo_execution.transition_outbox WHERE tenant_id='tenant-a'");
   assert.equal(count.rows[0].n,1);
  });
  await t.test("same job name in other tenant remains independent",async()=>{
   const r=await service.execute(input("tenant-b","one"));assert.equal(r.revision,1);
   const rows=await pool.query("SELECT tenant_id,revision FROM halo_execution.work_items ORDER BY tenant_id");
   assert.deepEqual(rows.rows.map(x=>[x.tenant_id,Number(x.revision)]),[["tenant-a",1],["tenant-b",1]]);
  });
  await t.test("forced audit failure rolls back state and outbox",async()=>{
   await seed("rollback-tenant");
   await pool.query(`CREATE FUNCTION halo_execution.fail_test_audit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.tenant_id='rollback-tenant' THEN RAISE EXCEPTION 'audit forced failure'; END IF; RETURN NEW; END $$`);
   await pool.query("CREATE TRIGGER fail_test_audit BEFORE INSERT ON halo_execution.transition_audit FOR EACH ROW EXECUTE FUNCTION halo_execution.fail_test_audit()");
   await assert.rejects(()=>service.execute(input("rollback-tenant","rollback")) );
   const r=await pool.query("SELECT revision FROM halo_execution.work_items WHERE tenant_id='rollback-tenant'");
   assert.equal(Number(r.rows[0].revision),0);
   for(const table of ["transition_receipts","transition_audit","transition_outbox"]){
    const c=await pool.query(`SELECT count(*)::int AS n FROM halo_execution.${table} WHERE tenant_id='rollback-tenant'`);
    assert.equal(c.rows[0].n,0);
   }
  });
  await t.test("executor without tenant scope sees no work items",async()=>{
   const client=await pool.connect();
   try {
    await client.query("BEGIN");await client.query("SET LOCAL ROLE halo_workflow_executor");
    const result=await client.query("SELECT count(*)::int AS n FROM halo_execution.work_items");
    assert.equal(result.rows[0].n,0);await client.query("ROLLBACK");
   }finally{client.release();}
  });
 }finally{await pool.end();}
});
