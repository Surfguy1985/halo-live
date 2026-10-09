// End-to-end service test against disposable PostgreSQL.
// Requires HALO_WORKFLOW_TEST_DATABASE_URL pointing at halo_test_* DB.
import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {generateKeyPairSync,sign} from "node:crypto";
import {createEnterpriseWorkflowPipeline} from "./enterprise-pipeline.mjs";
import {createWorkflowHTTPServer} from "./http-server.mjs";
const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
const enabled=Boolean(url);
if(enabled && !/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw Error("Disposable halo_test_* database required");
test("signed HTTP request publishes exactly one tenant-scoped revision", {skip:!enabled},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:10});
 const admin=await pool.connect();
 let server;
 try {
  await admin.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  for(const file of ["001_workflow_publishing.sql","002_tenant_rls.sql","003_identity_memberships.sql","004_runtime_role.sql"]){
   if(file==="002_tenant_rls.sql") await admin.query(
    "DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
   const sql=await readFile(fileURLToPath(new URL("./migrations/"+file,import.meta.url)),"utf8");
   await admin.query(sql);
  }
  await admin.query(`INSERT INTO halo_workflow.identity_memberships
   (actor_id,tenant_id,active,industry_ids,permissions)
   VALUES($1,$2,true,$3::jsonb,$4::jsonb)`,["actor-a","tenant-a",'["construction"]','["workflow:publish"]']);
  const pair=generateKeyPairSync("rsa",{modulusLength:2048});
  const time=Math.floor(Date.now()/1000);
  const enc=x=>Buffer.from(JSON.stringify(x)).toString("base64url");
  const signed=enc({alg:"RS256",typ:"JWT",kid:"key-a"})+"."+
   enc({iss:"https://id.example.test",aud:"halo-test-api",sub:"actor-a",iat:time-5,exp:time+600});
  const jwt=signed+"."+sign("RSA-SHA256",Buffer.from(signed),pair.privateKey).toString("base64url");
  const gateway=createEnterpriseWorkflowPipeline({
   issuer:"https://id.example.test",audience:"halo-test-api",
   fetchJWKS:async()=>({keys:[{...pair.publicKey.export({format:"jwk"}),kid:"key-a",kty:"RSA",use:"sig",alg:"RS256"}]}),
   identityPool:pool,workflowPool:pool,enabled:true
  });
  server=createWorkflowHTTPServer({gateway,enabled:true});
  await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
  const endpoint="http://127.0.0.1:"+server.address().port+"/v1/workflow-templates/demo/publish";
  const payload={requestID:"request-one",expectedRevision:0,
   layout:{schemaVersion:1,tenantID:"tenant-a",industryID:"construction",
    templateID:"demo",templateVersion:1,blocks:[]}};
  const send=(token=jwt,body=payload)=>fetch(endpoint,{method:"POST",
   headers:{"authorization":"Bearer "+token,"content-type":"application/json",
    "idempotency-key":"request-one"},body:JSON.stringify(body)});
  const first=await send();
  assert.equal(first.status,200,await first.text().catch(()=>"[body unavailable]"));
  const repeated=await send();
  assert.equal(repeated.status,200);
  const denied=await send(jwt,{...payload,layout:{...payload.layout,tenantID:"tenant-b"}});
  assert.equal(denied.status,403);
  const audits=await pool.query("SELECT count(*)::int AS n FROM halo_workflow.publish_audit WHERE tenant_id=$1",["tenant-a"]);
  assert.equal(audits.rows[0].n,1);
  await pool.query("UPDATE halo_workflow.identity_memberships SET active=false WHERE actor_id='actor-a'");
  assert.equal((await send()).status,403);
 }finally{
  if(server)await new Promise(resolve=>server.close(resolve));
  admin.release();await pool.end();
 }
});
