import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {PostgresWorkflowStore} from "./postgres-store.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";

const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw new Error("Refusing to touch any database except halo_test_*");

test("Swift wire fixture -> Node publish handler -> real PostgreSQL transaction", {skip:!url},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:4});
 try{
  // Dedicated disposable database; independently provision only the publishing schema.
  await pool.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOBYPASSRLS; END IF; END $$");
  for(const file of ["001_workflow_publishing.sql","002_tenant_rls.sql","004_runtime_role.sql"])
   await pool.query(await readFile(new URL("./migrations/"+file,import.meta.url),"utf8"));

  const fixture=JSON.parse(await readFile(new URL("./fixtures/swift-publish-v1.json",import.meta.url),"utf8"));
  const publisher=new WorkflowTemplatePublisher(new PostgresWorkflowStore(pool));
  const handler=createWorkflowPublishHandler({enabled:true,publisher});
  const session={authenticated:true,actorID:"staging-admin",tenantID:"staging-tenant",
   industryIDs:["construction"],permissions:["workflow:publish"]};
  const makeRequest=(body=fixture)=>({
   method:"POST",path:"/v1/workflow-templates/construction-dispatch/publish",
   headers:{"content-type":"application/json","idempotency-key":body.requestID},
   body:JSON.stringify(body)
  });

  const first=await handler(makeRequest(),session);
  assert.equal(first.status,200,first.body);
  assert.deepEqual(JSON.parse(first.body),{templateID:"construction-dispatch",revision:1,templateVersion:1});
  const audit=await pool.query("SELECT tenant_id,actor_id,revision FROM halo_workflow.publish_audit WHERE tenant_id=$1",["staging-tenant"]);
  assert.equal(audit.rowCount,1);
  assert.equal(audit.rows[0].actor_id,"staging-admin");
  assert.equal(Number(audit.rows[0].revision),1);
  const saved=await pool.query("SELECT layout FROM halo_workflow.template_revisions WHERE tenant_id=$1 AND template_id=$2",
   ["staging-tenant","construction-dispatch"]);
  assert.equal(saved.rowCount,1);
  assert.deepEqual(saved.rows[0].layout,fixture.layout);

  const retry=await handler(makeRequest(),session);
  assert.equal(retry.status,200,retry.body);
  assert.deepEqual(JSON.parse(retry.body),JSON.parse(first.body));
  const auditCount=await pool.query("SELECT count(*)::int AS n FROM halo_workflow.publish_audit WHERE tenant_id=$1",["staging-tenant"]);
  assert.equal(auditCount.rows[0].n,1,"replay must not double-write");

  const stale=await handler(makeRequest({...fixture,requestID:"stale-new-key"}),session);
  assert.equal(stale.status,409,stale.body);
  assert.deepEqual(JSON.parse(stale.body),{error:"REVISION_CONFLICT"});

  const denied=await handler(makeRequest({...fixture,requestID:"cross-tenant-key"}),{...session,tenantID:"other-tenant"});
  assert.equal(denied.status,403);
  const noPermission=await handler(makeRequest({...fixture,requestID:"no-permission-key"}),{...session,permissions:[]});
  assert.equal(noPermission.status,403);
  const revisions=await pool.query("SELECT count(*)::int AS n FROM halo_workflow.template_revisions WHERE template_id=$1",["construction-dispatch"]);
  assert.equal(revisions.rows[0].n,1);
 }finally{await pool.end();}
});
