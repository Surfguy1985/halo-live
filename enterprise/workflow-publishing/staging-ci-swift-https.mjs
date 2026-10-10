// Exact-SHA, disposable Swift-to-backend HTTPS signoff harness. The trusted
// certificate, hostname mapping, database, Redis state, identity, and token
// exist only inside one GitHub Actions job.
import assert from "node:assert/strict";
import http from "node:http";
import https from "node:https";
import {generateKeyPairSync,randomBytes} from "node:crypto";
import {readFile} from "node:fs/promises";
import {fileURLToPath,pathToFileURL} from "node:url";
import {spawn} from "node:child_process";
import {assertCIStagingSwiftHTTPSConfiguration} from "./staging-ci-swift-https-admission.mjs";
import {createCIStagingWorkflowBootstrap} from "./staging-bootstrap.mjs";
import {createCIStagingRedis} from "./staging-ci-redis.mjs";
import {migrateCIStagingDatabase,signCIStagingToken} from "./staging-ci-deploy.mjs";

const loopback=address=>address==="127.0.0.1" || address==="::ffff:127.0.0.1" || address==="::1";

const listen=server=>new Promise((resolve,reject)=>{
 const cleanup=()=>{server.off("error",onError);server.off("listening",onListen);};
 const onError=error=>{cleanup();reject(error);};
 const onListen=()=>{cleanup();resolve(server.address());};
 server.once("error",onError);server.once("listening",onListen);
 server.listen(0,"127.0.0.1");
});

const close=server=>new Promise((resolve,reject)=>{
 if(!server?.listening){resolve();return;}
 server.close(error=>error?reject(error):resolve());
 if(typeof server.closeAllConnections==="function")server.closeAllConnections();
});

function runSwiftSignoff({executable,stagingURL,bearerToken,fixturePath}){
 return new Promise((resolve,reject)=>{
  const child=spawn(executable,[],{stdio:["ignore","pipe","pipe"],env:{
   PATH:process.env.PATH??"/usr/local/bin:/usr/bin:/bin",
   LANG:process.env.LANG??"C.UTF-8",
   HALO_SWIFT_STAGING_URL:stagingURL,
   HALO_SWIFT_BEARER_TOKEN:bearerToken,
   HALO_SWIFT_FIXTURE_PATH:fixturePath
  }});
  let stdout="",stderr="",settled=false;
  let timer;
  const finish=(error,value)=>{
   if(settled)return;settled=true;
   if(timer)clearTimeout(timer);
   if(error)reject(error);else resolve(value);
  };
  const append=(current,chunk)=>current.length<16384?(current+chunk).slice(0,16384):current;
  child.stdout.on("data",chunk=>{stdout=append(stdout,chunk);});
  child.stderr.on("data",chunk=>{stderr=append(stderr,chunk);});
  child.once("error",error=>finish(error));
  child.once("close",code=>code===0
   ? finish(undefined,stdout)
   : finish(new Error(`Swift HTTPS signoff exited ${code}: ${stderr.slice(0,4096)}`)));
  timer=setTimeout(()=>{
   child.kill("SIGKILL");finish(new Error("Swift HTTPS signoff timed out"));
  },60000);
 });
}

function createLoopbackTLSProxy({certificate,privateKey,backendPort,hostname,counters}){
 let expectedAuthority;
 const server=https.createServer({cert:certificate,key:privateKey,minVersion:"TLSv1.2"},(request,response)=>{
  counters.requests++;
  counters.protocols.add(request.socket.getProtocol());
  if(!loopback(request.socket.remoteAddress) || request.socket.servername!==hostname ||
     request.headers.host!==expectedAuthority){
   response.writeHead(421,{"content-type":"application/json","cache-control":"no-store"});
   response.end(JSON.stringify({error:"MISDIRECTED_REQUEST"}));return;
  }
  const headers={...request.headers,host:`127.0.0.1:${backendPort}`};
  for(const name of ["connection","keep-alive","proxy-authenticate","proxy-authorization",
   "te","trailer","transfer-encoding","upgrade"]) delete headers[name];
  const upstream=http.request({hostname:"127.0.0.1",port:backendPort,path:request.url,
   method:request.method,headers},upstreamResponse=>{
   if((upstreamResponse.statusCode??500)>=300 && (upstreamResponse.statusCode??500)<400){
    counters.redirects++;
   }
   const responseHeaders={...upstreamResponse.headers};
   for(const name of ["connection","keep-alive","transfer-encoding","upgrade"]) delete responseHeaders[name];
   response.writeHead(upstreamResponse.statusCode??502,responseHeaders);
   upstreamResponse.pipe(response);
  });
  upstream.setTimeout(20000,()=>upstream.destroy(new Error("Upstream timeout")));
  upstream.once("error",()=>{
   if(!response.headersSent)response.writeHead(502,{"content-type":"application/json","cache-control":"no-store"});
   response.end(JSON.stringify({error:"BAD_GATEWAY"}));
  });
  request.pipe(upstream);
 });
 server.on("tlsClientError",()=>{counters.tlsErrors++;});
 server.on("clientError",(_error,socket)=>socket.destroy());
 return {server,setAuthority:value=>{expectedAuthority=value;}};
}

export async function runCIStagingSwiftHTTPS(config=process.env){
 const admission=assertCIStagingSwiftHTTPSConfiguration(config);
 const {Pool}=await import("pg");
 const admin=new Pool({connectionString:config.HALO_WORKFLOW_DATABASE_URL,max:3});
 let identityPool,workflowPool,app,tlsServer;
 try{
  await migrateCIStagingDatabase(admin);
  const workflowPassword=randomBytes(32).toString("hex");
  const identityPassword=randomBytes(32).toString("hex");
  await admin.query(`ALTER ROLE halo_workflow_runtime PASSWORD '${workflowPassword}'`);
  await admin.query(`ALTER ROLE halo_identity_runtime PASSWORD '${identityPassword}'`);
  const fixtureURL=new URL("./fixtures/swift-publish-v1.json",import.meta.url);
  const fixture=JSON.parse(await readFile(fixtureURL,"utf8"));
  await admin.query(`INSERT INTO halo_workflow.identity_memberships
   (actor_id,tenant_id,active,industry_ids,permissions)
   VALUES($1,$2,true,$3::jsonb,$4::jsonb)`,[
    "staging-actor",fixture.layout.tenantID,JSON.stringify([fixture.layout.industryID]),
    JSON.stringify(["workflow:publish"])
  ]);

  const poolOptions={host:"127.0.0.1",port:5432,database:admission.databaseName,ssl:false,max:4};
  identityPool=new Pool({...poolOptions,user:admission.identityUser,password:identityPassword});
  workflowPool=new Pool({...poolOptions,user:admission.workflowUser,password:workflowPassword});
  const redis=createCIStagingRedis({url:config.HALO_WORKFLOW_REDIS_URL});
  const keys=generateKeyPairSync("rsa",{modulusLength:2048});
  const publicJWK={...keys.publicKey.export({format:"jwk"}),kid:"ci-ephemeral",kty:"RSA",use:"sig",alg:"RS256"};
  const logs=[];
  app=createCIStagingWorkflowBootstrap({config,identityPool,workflowPool,redis,
   fetchJWKS:async()=>({keys:[publicJWK]}),logger:event=>logs.push(event)});
  const backendAddress=await app.start();
  assert.deepEqual(backendAddress.host,"127.0.0.1");

  const counters={requests:0,redirects:0,tlsErrors:0,protocols:new Set()};
  const proxy=createLoopbackTLSProxy({
   certificate:await readFile(config.HALO_SWIFT_TLS_CERTIFICATE),
   privateKey:await readFile(config.HALO_SWIFT_TLS_PRIVATE_KEY),
   backendPort:backendAddress.port,hostname:admission.publicHost,counters
  });
  tlsServer=proxy.server;
  const tlsAddress=await listen(tlsServer);
  const authority=`${admission.publicHost}:${tlsAddress.port}`;
  proxy.setAuthority(authority);
  const token=signCIStagingToken(keys.privateKey,config);
  const swiftOutput=await runSwiftSignoff({
   executable:config.HALO_SWIFT_SIGNOFF_EXECUTABLE,
   stagingURL:`https://${authority}/`,bearerToken:token,
   fixturePath:fileURLToPath(fixtureURL)
  });
  const swiftSummary=JSON.parse(swiftOutput);
  assert.deepEqual(swiftSummary,{
   transport:"swift-urlsession-trusted-https",publish:"passed",
   idempotentReplay:"passed",reconciliation:"passed",
   authorizationFailure:"passed",revisionConflict:"passed"
  });
  assert.equal(counters.requests,5);
  assert.equal(counters.redirects,0);
  assert.equal(counters.tlsErrors,0);
  assert.ok(counters.protocols.size>=1);
  assert.ok([...counters.protocols].every(protocol=>protocol==="TLSv1.2" || protocol==="TLSv1.3"));

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
  assert.ok(logs.every(event=>!JSON.stringify(event).includes(token)));

  return Object.freeze({releaseSHA:admission.releaseSHA,tests:"passed",
   transport:"swift-urlsession-trusted-https",tlsProtocols:[...counters.protocols].sort(),
   redirects:0,revisions:1,audits:1,idempotency:1,outboundSideEffects:0});
 }finally{
  if(tlsServer)await close(tlsServer).catch(()=>{});
  if(app)await app.stop().catch(()=>{});
  if(identityPool)await identityPool.end().catch(()=>{});
  if(workflowPool)await workflowPool.end().catch(()=>{});
  await admin.end().catch(()=>{});
 }
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href){
 runCIStagingSwiftHTTPS().then(summary=>process.stdout.write(JSON.stringify(summary)+"\n"),error=>{
  process.stderr.write("HALO Swift HTTPS staging signoff failed: "+error.message+"\n");process.exitCode=1;
 });
}
