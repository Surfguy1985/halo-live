import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import {createStagingWorkflowBootstrap} from "./staging-bootstrap.mjs";

const valid = () => ({
 HALO_DEPLOYMENT_ENV:"staging",
 HALO_WORKFLOW_PUBLISH_ENABLED:"true",
 HALO_WORKFLOW_DEPLOYMENT_APPROVED:"staging-only",
 HALO_WORKFLOW_BIND_HOST:"127.0.0.1",
 HALO_WORKFLOW_PUBLIC_URL:"https://api.staging.halo.example",
 HALO_WORKFLOW_AUTH_ISSUER:"https://identity.example.test/issuer",
 HALO_WORKFLOW_AUTH_AUDIENCE:"halo-staging-workflow",
 HALO_WORKFLOW_DATABASE_URL:"postgresql://user:secret@db.example.test/halo_staging_workflow?sslmode=verify-full",
 HALO_WORKFLOW_PORT:"0",
 HALO_WORKFLOW_EPHEMERAL_TEST_ONLY:"true"
});
const deps=({healthy=true}={})=>{
 const health={healthy};
 const calls={identity:0,workflow:0,jwks:0,redis:0};
 const identityPool={query:async()=>{calls.identity++;return {rows:[]};}};
 const workflowPool={
  query:async()=>{calls.workflow++;if(!health.healthy)throw Error("db unavailable");
   return {rows:[{ready:1}]};},
  connect:async()=>{throw Error("No workflow SQL expected");}
 };
 const redis={
  ping:async()=>{calls.redis++;return "PONG";},
  eval:async()=>1
 };
 const fetchJWKS=async()=>{calls.jwks++;throw Error("No JWKS expected for unsigned requests");};
 return {identityPool,workflowPool,redis,fetchJWKS,calls,health};
};
test("invalid deployment configuration denies before touching dependencies",()=>{
 const d=deps();
 assert.throws(()=>createStagingWorkflowBootstrap({
  config:{...valid(),HALO_DEPLOYMENT_ENV:"production"},...d
 }),{message:"HALO workflow staging admission denied"});
 assert.deepEqual(d.calls,{identity:0,workflow:0,jwks:0,redis:0});
});
test("bootstrap rejects shared identity/workflow pool and missing Redis",()=>{
 const d=deps();
 assert.throws(()=>createStagingWorkflowBootstrap({
  config:valid(),...d,identityPool:d.workflowPool
 }),{message:"HALO staging bootstrap denied"});
 assert.throws(()=>createStagingWorkflowBootstrap({
  config:valid(),...d,redis:undefined
 }),{message:"HALO staging bootstrap denied"});
});
test("bootstrap rejects malformed ports before opening a listener",()=>{
 for(const port of ["-1","65536","1.5","abc","",undefined]){
  assert.throws(()=>createStagingWorkflowBootstrap({
   config:{...valid(),HALO_WORKFLOW_PORT:port},...deps()
  }),{message:"HALO staging bootstrap denied"});
 }
});
test("unhealthy PostgreSQL prevents binding and fails closed",async()=>{
 const d=deps({healthy:false});
 const app=createStagingWorkflowBootstrap({config:valid(),...d});
 await assert.rejects(app.start(),{message:"HALO staging bootstrap denied"});
 assert.ok(d.calls.workflow>0);
 assert.equal(d.calls.identity,0);
});
test("staging binds only loopback, denies unsigned publishing, and closes cleanly",async()=>{
 const d=deps();
 const app=createStagingWorkflowBootstrap({config:valid(),...d});
 const address=await app.start();
 try{
  assert.equal(address.host,"127.0.0.1");
  assert.ok(address.port>0);
  const base="http://127.0.0.1:"+address.port;
  const ready=await fetch(base+"/health/ready");
  assert.equal(ready.status,200);
  assert.deepEqual(await ready.json(),{status:"ready"});
  const publish=await fetch(base+"/v1/workflow-templates/demo/publish",{
   method:"POST",headers:{"content-type":"application/json","idempotency-key":"demo"},
   body:"{}"
  });
  assert.equal(publish.status,401);
  assert.deepEqual(await publish.json(),{error:"UNAUTHENTICATED"});
  assert.equal(d.calls.identity,0);
  assert.equal(d.calls.jwks,0);
  await assert.rejects(app.start(),{message:"HALO staging bootstrap denied"});
 }finally{await app.stop();}
});

test("ephemeral listener port requires explicit test-only flag",()=>{
 const d=deps();
 assert.throws(()=>createStagingWorkflowBootstrap({
  config:{...valid(),HALO_WORKFLOW_EPHEMERAL_TEST_ONLY:undefined},...d
 }),{message:"HALO staging bootstrap denied"});
});
test("losing PostgreSQL readiness after startup blocks mutations before auth or SQL",async()=>{
 const d=deps();
 const app=createStagingWorkflowBootstrap({config:valid(),...d});
 const {port}=await app.start();
 try {
  d.health.healthy=false;
  const base="http://127.0.0.1:"+port;
  const ready=await fetch(base+"/health/ready");
  assert.equal(ready.status,503);
  const publish=await fetch(base+"/v1/workflow-templates/demo/publish",{
   method:"POST",headers:{"content-type":"application/json","idempotency-key":"demo"},
   body:"{}"
  });
  assert.equal(publish.status,503);
  assert.deepEqual(await publish.json(),{error:"STAGING_NOT_READY"});
  assert.equal(d.calls.identity,0);
  assert.equal(d.calls.jwks,0);
 } finally {await app.stop();}
});
test("lost Redis readiness blocks publishing even if database remains healthy",async()=>{
 const d=deps();
 const app=createStagingWorkflowBootstrap({config:valid(),...d});
 const {port}=await app.start();
 try {
  d.redis.ping=async()=>{throw Error("redis offline");};
  const r=await fetch("http://127.0.0.1:"+port+"/v1/workflow-templates/demo/publish",{
   method:"POST",headers:{"content-type":"application/json"},body:"{}"
  });
  assert.equal(r.status,503);
  assert.deepEqual(await r.json(),{error:"STAGING_NOT_READY"});
  assert.equal(d.calls.identity,0);
 } finally {await app.stop();}
});
test("concurrent start and stop during startup are denied without opening extra listeners",async()=>{
 const d=deps();
 let release;
 const pending=new Promise(resolve=>{release=resolve;});
 d.workflowPool.query=async()=>{await pending;return {rows:[{ready:1}]};};
 const app=createStagingWorkflowBootstrap({config:valid(),...d});
 const first=app.start();
 try {
  await assert.rejects(app.start(),{message:"HALO staging bootstrap denied"});
  await assert.rejects(app.stop(),{message:"HALO staging bootstrap denied"});
 } finally {release();}
 const address=await first;
 assert.ok(address.port>0);
 await app.stop();
 await app.stop(); // idempotent shutdown
});
test("occupied staging port fails cleanly and can be retried after release",async()=>{
 const listener=net.createServer();
 await new Promise(resolve=>listener.listen(0,"127.0.0.1",resolve));
 const port=listener.address().port;
 const app=createStagingWorkflowBootstrap({
  config:{...valid(),HALO_WORKFLOW_PORT:String(port)},...deps()
 });
 try {
  await assert.rejects(app.start(),error=>error?.code==="EADDRINUSE");
  await app.stop();
 } finally {
  await new Promise(resolve=>listener.close(resolve));
 }
 const address=await app.start();
 assert.equal(address.port,port);
 await app.stop();
});
