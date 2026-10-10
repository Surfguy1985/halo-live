// Disposable GitHub Actions deployment harness. Admission constrains this to a
// synthetic loopback-only database, Redis, issuer and public origin.
import assert from "node:assert/strict";
import {randomBytes,generateKeyPairSync,sign} from "node:crypto";
import {readFile,readdir} from "node:fs/promises";
import {pathToFileURL} from "node:url";
import {assertCIStagingWorkflowConfiguration} from "./staging-ci-admission.mjs";
import {createCIStagingWorkflowBootstrap} from "./staging-bootstrap.mjs";
import {createCIStagingRedis} from "./staging-ci-redis.mjs";

const jsonClone=value=>JSON.parse(JSON.stringify(value));
const b64=value=>Buffer.from(JSON.stringify(value)).toString("base64url");

async function migrate(admin){
 await admin.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
 await admin.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
 await admin.query(`DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN
   CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB
    NOCREATEROLE NOREPLICATION NOBYPASSRLS;
  END IF;
 END $$`);
 const files=(await readdir(new URL("./migrations/",import.meta.url)))
  .filter(name=>/^\d{3}_[a-z0-9_]+\.sql$/.test(name)).sort();
 assert.equal(files.length,24);
 for(let index=0;index<files.length;index++){
  assert.equal(Number(files[index].slice(0,3)),index+1);
  await admin.query(await readFile(new URL("./migrations/"+files[index],import.meta.url),"utf8"));
 }
}

const signToken=(privateKey,config,subject="staging-actor")=>{
 const now=Math.floor(Date.now()/1000);
 const unsigned=b64({alg:"RS256",typ:"JWT",kid:"ci-ephemeral"})+"."+
  b64({iss:config.HALO_WORKFLOW_AUTH_ISSUER,aud:config.HALO_WORKFLOW_AUTH_AUDIENCE,
   sub:subject,iat:now-5,exp:now+600});
 return unsigned+"."+sign("RSA-SHA256",Buffer.from(unsigned),privateKey).toString("base64url");
};

async function responseJSON(response){
 assert.match(response.headers.get("content-type")??"",/^application\/json/);
 return response.json();
}

export async function runCIStagingDeployment(config=process.env){
 const admission=assertCIStagingWorkflowConfiguration(config);
 const {Pool}=await import("pg");
 const admin=new Pool({connectionString:config.HALO_WORKFLOW_DATABASE_URL,max:3});
 let identityPool,workflowPool,app;
 try{
  await migrate(admin);
  const workflowPassword=randomBytes(32).toString("hex");
  const identityPassword=randomBytes(32).toString("hex");
  await admin.query(`ALTER ROLE halo_workflow_runtime PASSWORD '${workflowPassword}'`);
  await admin.query(`ALTER ROLE halo_identity_runtime PASSWORD '${identityPassword}'`);
  const fixture=JSON.parse(await readFile(new URL("./fixtures/swift-publish-v1.json",import.meta.url),"utf8"));
  await admin.query(`INSERT INTO halo_workflow.identity_memberships
   (actor_id,tenant_id,active,industry_ids,permissions)
   VALUES($1,$2,true,$3::jsonb,$4::jsonb)`,[
    "staging-actor",fixture.layout.tenantID,JSON.stringify([fixture.layout.industryID]),
    JSON.stringify(["workflow:publish"])
  ]);

  const poolOptions={host:"127.0.0.1",port:5432,database:admission.databaseName,ssl:false,max:4};
  identityPool=new Pool({...poolOptions,user:admission.identityUser,password:identityPassword});
  workflowPool=new Pool({...poolOptions,user:admission.workflowUser,password:workflowPassword});
  const rawRedis=createCIStagingRedis({url:config.HALO_WORKFLOW_REDIS_URL});
  let redisAvailable=true;
  const redis={
   ping:()=>redisAvailable?rawRedis.ping():Promise.reject(new Error("CI readiness fault")),
   eval:(...args)=>rawRedis.eval(...args)
  };
  const keys=generateKeyPairSync("rsa",{modulusLength:2048});
  const publicJWK={...keys.publicKey.export({format:"jwk"}),kid:"ci-ephemeral",kty:"RSA",use:"sig",alg:"RS256"};
  const logs=[];
  app=createCIStagingWorkflowBootstrap({config,identityPool,workflowPool,redis,
   fetchJWKS:async()=>({keys:[publicJWK]}),logger:event=>logs.push(event)});
  const address=await app.start();
  assert.equal(address.host,"127.0.0.1");
  const base=`http://127.0.0.1:${address.port}`;
  const live=await fetch(base+"/health/live");
  assert.equal(live.status,200);assert.deepEqual(await responseJSON(live),{status:"alive"});
  const ready=await fetch(base+"/health/ready");
  assert.equal(ready.status,200);assert.deepEqual(await responseJSON(ready),{status:"ready"});

  const jwt=signToken(keys.privateKey,config);
  const route=`/v1/workflow-templates/${fixture.layout.templateID}`;
  const send=async({body=fixture,key=body.requestID,token=jwt,action="publish"}={})=>{
   const response=await fetch(base+route+"/"+action,{method:"POST",headers:{
    authorization:"Bearer "+token,"content-type":"application/json","accept":"application/json",
    "idempotency-key":key
   },body:JSON.stringify(body)});
   return {status:response.status,body:await responseJSON(response)};
  };
  const receipt={templateID:fixture.layout.templateID,revision:1,templateVersion:fixture.layout.templateVersion};
  assert.deepEqual(await send(),{status:200,body:receipt});
  assert.deepEqual(await send(),{status:200,body:receipt});
  assert.deepEqual(await send({action:"reconcile"}),{status:200,body:{
   requestID:fixture.requestID,outcome:"COMMITTED",result:receipt
  }});

  const unseen={...jsonClone(fixture),requestID:"22222222-2222-3333-4444-555555555555"};
  assert.deepEqual(await send({body:unseen,action:"reconcile"}),
   {status:404,body:{error:"PUBLISH_REQUEST_NOT_FOUND"}});
  const altered={...jsonClone(fixture),expectedRevision:1};
  assert.deepEqual(await send({body:altered}),{status:409,body:{error:"IDEMPOTENCY_CONFLICT"}});
  const stale={...jsonClone(fixture),requestID:"33333333-2222-3333-4444-555555555555"};
  assert.deepEqual(await send({body:stale}),{status:409,body:{error:"REVISION_CONFLICT"}});
  assert.deepEqual(await send({key:"mismatched-request-id"}),{status:422,body:{error:"INVALID_REQUEST"}});
  assert.deepEqual(await send({token:"invalid.jwt.signature"}),{status:401,body:{error:"UNAUTHENTICATED"}});
  const wrongTenant={...jsonClone(fixture),requestID:"44444444-2222-3333-4444-555555555555"};
  wrongTenant.layout.tenantID="another-tenant";
  assert.deepEqual(await send({body:wrongTenant}),{status:403,body:{error:"FORBIDDEN"}});
  const invalidSchema={...jsonClone(fixture),requestID:"55555555-2222-3333-4444-555555555555"};
  invalidSchema.layout.schemaVersion=999;
  assert.deepEqual(await send({body:invalidSchema}),{status:422,body:{error:"INVALID"}});

  const durable=await admin.query(`SELECT
   (SELECT count(*)::integer FROM halo_workflow.template_revisions) AS revisions,
   (SELECT count(*)::integer FROM halo_workflow.publish_audit) AS audits,
   (SELECT count(*)::integer FROM halo_workflow.publish_idempotency) AS idempotency,
   (SELECT actor_id FROM halo_workflow.publish_audit LIMIT 1) AS actor`);
  assert.deepEqual(durable.rows[0],{revisions:1,audits:1,idempotency:1,actor:"staging-actor"});
  const sideEffects=await admin.query(`SELECT
   (SELECT count(*)::integer FROM halo_execution.transition_outbox) AS transition_outbox,
   (SELECT count(*)::integer FROM halo_execution.consumer_deliveries) AS consumer_deliveries,
   (SELECT count(*)::integer FROM halo_execution.delivery_receipts) AS delivery_receipts,
   (SELECT count(*)::integer FROM halo_execution.integration_registrations) AS integrations,
   (SELECT count(*)::integer FROM halo_execution.dispatch_permits) AS dispatch_permits,
   (SELECT count(*)::integer FROM halo_execution.delivery_outcome_audit) AS delivery_outcomes`);
  assert.ok(Object.values(sideEffects.rows[0]).every(value=>value===0));

  await admin.query("UPDATE halo_workflow.identity_memberships SET active=false WHERE actor_id='staging-actor'");
  const revoked={...jsonClone(fixture),requestID:"66666666-2222-3333-4444-555555555555"};
  assert.deepEqual(await send({body:revoked}),{status:403,body:{error:"FORBIDDEN"}});
  redisAvailable=false;
  const unavailable={...jsonClone(fixture),requestID:"77777777-2222-3333-4444-555555555555"};
  assert.deepEqual(await send({body:unavailable,token:"invalid.jwt.signature"}),
   {status:503,body:{error:"STAGING_NOT_READY"}});
  const finalCount=await admin.query("SELECT count(*)::integer AS n FROM halo_workflow.template_revisions");
  assert.equal(finalCount.rows[0].n,1);
  assert.ok(logs.every(event=>!JSON.stringify(event).includes(jwt)));

  return Object.freeze({releaseSHA:admission.releaseSHA,tests:"passed",revisions:1,audits:1,
   idempotency:1,outboundSideEffects:0,transport:"loopback-http-backend-only"});
 }finally{
  if(app)await app.stop().catch(()=>{});
  if(identityPool)await identityPool.end().catch(()=>{});
  if(workflowPool)await workflowPool.end().catch(()=>{});
  await admin.end().catch(()=>{});
 }
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
 runCIStagingDeployment().then(summary=>process.stdout.write(JSON.stringify(summary)+"\n"),error=>{
  process.stderr.write("HALO isolated staging deployment failed: "+error.message+"\n");process.exitCode=1;
 });
}
