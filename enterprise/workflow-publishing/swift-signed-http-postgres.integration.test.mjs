// Signed HTTP -> trusted membership -> real PostgreSQL, using the
// Swift JSONEncoder fixture verified separately by macOS CI.
// Runs ONLY against a disposable halo_test_* database.
import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {generateKeyPairSync,sign} from "node:crypto";
import {createEnterpriseWorkflowPipeline} from "./enterprise-pipeline.mjs";
import {createWorkflowHTTPServer} from "./http-server.mjs";

const connectionString=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(connectionString && !/^halo_test_[a-z0-9_]+$/i.test(new URL(connectionString).pathname.slice(1)))
 throw new Error("Refusing non-disposable database");

test("Swift fixture crosses signed HTTP auth and durable tenant-scoped PostgreSQL transaction",
 {skip:!connectionString}, async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString,max:8});
 let server;
 try {
  await pool.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  for(const file of ["001_workflow_publishing.sql","002_tenant_rls.sql",
                     "003_identity_memberships.sql","004_runtime_role.sql"])
   await pool.query(await readFile(new URL("./migrations/"+file,import.meta.url),"utf8"));
  const fixture=JSON.parse(await readFile(new URL("./fixtures/swift-publish-v1.json",import.meta.url),"utf8"));
  await pool.query(`INSERT INTO halo_workflow.identity_memberships
   (actor_id,tenant_id,active,industry_ids,permissions)
   VALUES($1,$2,true,$3::jsonb,$4::jsonb)`,
   ["swift-admin",fixture.layout.tenantID,JSON.stringify([fixture.layout.industryID]),JSON.stringify(["workflow:publish"])]);
  const pair=generateKeyPairSync("rsa",{modulusLength:2048});
  const now=Math.floor(Date.now()/1000);
  const b64=x=>Buffer.from(JSON.stringify(x)).toString("base64url");
  const unsigned=b64({alg:"RS256",typ:"JWT",kid:"swift-fixture-key"})+"."+
   b64({iss:"https://id.example.test",aud:"halo-test-api",sub:"swift-admin",iat:now-5,exp:now+600});
  const jwt=unsigned+"."+sign("RSA-SHA256",Buffer.from(unsigned),pair.privateKey).toString("base64url");
  const gateway=createEnterpriseWorkflowPipeline({
   issuer:"https://id.example.test",audience:"halo-test-api",
   fetchJWKS:async()=>({keys:[{...pair.publicKey.export({format:"jwk"}),kid:"swift-fixture-key",kty:"RSA",use:"sig",alg:"RS256"}]}),
   identityPool:pool,workflowPool:pool,enabled:true
  });
  // Simulate a committed publish whose response is lost between the gateway
  // and HTTP transport. The client must reconcile using the *same* request ID.
  let loseFirstCommittedReceipt=true;
  const unreliableGateway=async request=>{
   const result=await gateway(request);
   if(loseFirstCommittedReceipt && result.status===200){
    loseFirstCommittedReceipt=false;
    throw new Error("SIMULATED_LOST_RECEIPT_AFTER_COMMIT");
   }
   return result;
  };
  server=createWorkflowHTTPServer({gateway:unreliableGateway,enabled:true});
  await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
  const endpoint="http://127.0.0.1:"+server.address().port+
   "/v1/workflow-templates/"+fixture.layout.templateID+"/publish";
  const send=(body=fixture,{token=jwt,key=body.requestID}={})=>fetch(endpoint,{
   method:"POST",headers:{"authorization":"Bearer "+token,
    "content-type":"application/json","idempotency-key":key},body:JSON.stringify(body)
  });
  const lost=await send();
  assert.equal(lost.status,500,"simulated lost receipt must not look successful");
  assert.deepEqual(await lost.json(),{error:"INTERNAL"},
   "internal transport failure must not leak details");
  const committedBeforeRetry=await pool.query(`SELECT count(*)::int AS n
   FROM halo_workflow.template_revisions WHERE tenant_id=$1 AND template_id=$2`,
   [fixture.layout.tenantID,fixture.layout.templateID]);
  assert.equal(committedBeforeRetry.rows[0].n,1,
   "first publish committed even though client did not receive a receipt");
  const reconciled=await send();
  const firstBody=await reconciled.text();
  assert.equal(reconciled.status,200,firstBody);
  const receipt=JSON.parse(firstBody);
  assert.deepEqual(receipt,{templateID:fixture.layout.templateID,revision:1,templateVersion:fixture.layout.templateVersion});
  const saved=await pool.query(`SELECT layout,revision FROM halo_workflow.template_revisions
   WHERE tenant_id=$1 AND template_id=$2`,[fixture.layout.tenantID,fixture.layout.templateID]);
  assert.equal(saved.rowCount,1);
  assert.deepEqual(saved.rows[0].layout,fixture.layout);
  assert.equal(Number(saved.rows[0].revision),1);

  const replay=await send();
  assert.equal(replay.status,200);
  assert.deepEqual(await replay.json(),receipt);
  const afterReconcile=await pool.query(`SELECT
   (SELECT count(*)::int FROM halo_workflow.template_revisions
     WHERE tenant_id=$1 AND template_id=$2) AS revisions,
   (SELECT count(*)::int FROM halo_workflow.publish_audit
     WHERE tenant_id=$1 AND template_id=$2) AS audits,
   (SELECT count(*)::int FROM halo_workflow.publish_idempotency
     WHERE tenant_id=$1 AND template_id=$2) AS idempotency`,
   [fixture.layout.tenantID,fixture.layout.templateID]);
  assert.deepEqual(afterReconcile.rows[0],
   {revisions:1,audits:1,idempotency:1},
   "lost receipt plus exact replay must create one durable revision, audit and key");
  // A client that generates a new request ID instead of reconciling the
  // original request must receive a conflict, never a second revision.
  const incorrectRetry=await send({...fixture,requestID:"incorrect-retry-new-key"});
  assert.equal(incorrectRetry.status,409);
  assert.deepEqual(await incorrectRetry.json(),{error:"REVISION_CONFLICT"});
  const reconcileEndpoint=endpoint.replace(/\/publish$/,"/reconcile");
  const check=(requestID,token=jwt)=>fetch(reconcileEndpoint,{
   method:"POST",headers:{"authorization":"Bearer "+token,
    "content-type":"application/json","idempotency-key":requestID},
   body:JSON.stringify({requestID})
  });
  const confirmed=await check(fixture.requestID);
  assert.equal(confirmed.status,200);
  assert.deepEqual(await confirmed.json(),{status:"committed",receipt});
  const missing=await check("not-published");
  assert.equal(missing.status,404);
  assert.deepEqual(await missing.json(),{error:"RECEIPT_NOT_FOUND"});
  assert.equal((await check(fixture.requestID,"invalid.jwt.signature")).status,401);
  const noWrite=await pool.query(`SELECT
   (SELECT count(*)::int FROM halo_workflow.template_revisions WHERE tenant_id=$1) AS revisions,
   (SELECT count(*)::int FROM halo_workflow.publish_audit WHERE tenant_id=$1) AS audits,
   (SELECT count(*)::int FROM halo_workflow.publish_idempotency WHERE tenant_id=$1) AS receipts`,
   [fixture.layout.tenantID]);
  assert.deepEqual(noWrite.rows[0],{revisions:1,audits:1,receipts:1},
   "reconciliation must not mutate durable workflow state");
  const altered=await send({...fixture,expectedRevision:1});
  assert.equal(altered.status,409,"same idempotency key cannot be reused for a different revision");
  assert.deepEqual(await altered.json(),{error:"IDEMPOTENCY_CONFLICT"});
  const stale=await send({...fixture,requestID:"stale-swift-request"});
  assert.equal(stale.status,409);
  assert.deepEqual(await stale.json(),{error:"REVISION_CONFLICT"});
  const wrongTenant=await send({...fixture,requestID:"wrong-tenant-request",
   layout:{...fixture.layout,tenantID:"other-tenant"}});
  assert.equal(wrongTenant.status,403);
  const invalidToken=await send(fixture,{token:"invalid.jwt.signature"});
  assert.equal(invalidToken.status,401);
  const mismatchedHeader=await send(fixture,{key:"different-header"});
  assert.equal(mismatchedHeader.status,422);
  const audit=await pool.query(`SELECT actor_id,revision,content_sha256 FROM halo_workflow.publish_audit
   WHERE tenant_id=$1`,[fixture.layout.tenantID]);
  assert.equal(audit.rowCount,1);
  assert.equal(audit.rows[0].actor_id,"swift-admin");
  assert.equal(Number(audit.rows[0].revision),1);
  assert.equal(audit.rows[0].content_sha256.length,64);

  await pool.query("UPDATE halo_workflow.identity_memberships SET active=false WHERE actor_id=$1",["swift-admin"]);
  const revoked=await send({...fixture,requestID:"after-revocation"});
  assert.equal(revoked.status,403);
  const counts=await pool.query(`SELECT count(*)::integer AS n FROM halo_workflow.template_revisions
   WHERE tenant_id=$1`,[fixture.layout.tenantID]);
  assert.equal(counts.rows[0].n,1,"failed and revoked requests must not write");
 }finally{
  if(server)await new Promise(resolve=>server.close(resolve));
  await pool.end();
 }
});
