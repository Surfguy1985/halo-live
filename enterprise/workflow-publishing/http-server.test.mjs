import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import {createWorkflowHTTPServer} from "./http-server.mjs";
async function withServer(options,run){
 const server=createWorkflowHTTPServer(options);
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 try {return await run("http://127.0.0.1:"+server.address().port);}
 finally {await new Promise(resolve=>server.close(resolve));}
}
test("disabled HTTP endpoint never calls service",()=>withServer({
 gateway:async()=>{throw Error("must not call");},enabled:false
},async url=>assert.equal((await fetch(url+"/v1/workflow-templates/a/publish",{method:"POST"})).status,404)));
test("rejects unsupported paths and methods",()=>withServer({
 gateway:async()=>{throw Error("must not call");},enabled:true
},async url=>{
 assert.equal((await fetch(url+"/unknown")).status,404);
 assert.equal((await fetch(url+"/v1/workflow-templates/a/publish")).status,405);
}));
test("forwards bounded body and headers to isolated gateway",()=>withServer({
 enabled:true,gateway:async req=>{
  assert.equal(req.method,"POST");
  assert.equal(req.headers["idempotency-key"],"key");
  assert.equal(req.body.toString(),"{}");
  return {status:200,body:JSON.stringify({revision:1})};
 }
},async url=>{
 const response=await fetch(url+"/v1/workflow-templates/a/publish",{
  method:"POST",headers:{"content-type":"application/json","idempotency-key":"key"},body:"{}"});
 assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{revision:1});
}));
test("oversized body rejected without invoking gateway",()=>withServer({
 enabled:true,gateway:async()=>{throw Error("must not call");}
},async url=>{
 const response=await fetch(url+"/v1/workflow-templates/a/publish",{
  method:"POST",body:"x".repeat(132000)});
 assert.equal(response.status,413);
}));

test("liveness is available without exposing tenant data",()=>withServer({
 gateway:async()=>{throw Error("must not call");},enabled:false
},async url=>{
 const response=await fetch(url+"/health/live");
 assert.equal(response.status,200);
 assert.deepEqual(await response.json(),{status:"alive"});
}));
test("integrated per-peer guard returns 429 before gateway on excess traffic",()=>withServer({
 enabled:true,rateLimit:1,rateWindowMs:60000,
 gateway:async()=>({status:200,body:"{}"})
},async url=>{
 const endpoint=url+"/v1/workflow-templates/a/publish";
 const options={method:"POST",headers:{"content-type":"application/json"},body:"{}"};
 assert.equal((await fetch(endpoint,options)).status,200);
 assert.equal((await fetch(endpoint,options)).status,429);
}));

test("readiness fails closed unless explicitly configured and healthy",()=>withServer({
 enabled:true,gateway:async()=>({status:200,body:"{}"})
},async url=>{
 assert.equal((await fetch(url+"/health/ready")).status,503);
}));
test("readiness reports dependencies only when check passes",()=>withServer({
 enabled:true,readinessCheck:async()=>true,gateway:async()=>({status:200,body:"{}"})
},async url=>{
 const r=await fetch(url+"/health/ready");
 assert.equal(r.status,200);
 assert.deepEqual(await r.json(),{status:"ready"});
}));

test("shared Redis limiter is used instead of local limiter when configured",()=>withServer({
 enabled:true,rateLimit:1,rateLimitRedis:{eval:async()=>2},
 gateway:async()=>{throw Error("gateway must not run");}
},async url=>{
 const r=await fetch(url+"/v1/workflow-templates/a/publish",{method:"POST",body:"{}"});
 assert.equal(r.status,429);
}));
test("Redis limiter failure returns 503 without invoking workflow",()=>withServer({
 enabled:true,rateLimitRedis:{eval:async()=>{throw Error("cache down");}},
 gateway:async()=>{throw Error("gateway must not run");}
},async url=>{
 const r=await fetch(url+"/v1/workflow-templates/a/publish",{method:"POST",body:"{}"});
 assert.equal(r.status,503);
}));

function rawPost(url, headers) {
 return new Promise((resolve,reject)=>{
  const req=http.request(url,{method:"POST",headers},res=>{
   const chunks=[];res.on("data",chunk=>chunks.push(chunk));
   res.on("end",()=>resolve({status:res.statusCode,body:JSON.parse(Buffer.concat(chunks).toString())}));
  });
  req.on("error",reject);
  req.end("{}");
 });
}
test("duplicate idempotency keys are rejected before gateway processing",()=>withServer({
 enabled:true,gateway:async()=>{throw Error("gateway must not run");}
},async url=>{
 const response=await rawPost(url+"/v1/workflow-templates/a/publish",[
  "Content-Type","application/json",
  "Idempotency-Key","first",
  "idempotency-key","second"
 ]);
 assert.equal(response.status,400);
 assert.deepEqual(response.body,{error:"DUPLICATE_HEADER"});
}));
test("duplicate Authorization headers are rejected before gateway processing",()=>withServer({
 enabled:true,gateway:async()=>{throw Error("gateway must not run");}
},async url=>{
 const response=await rawPost(url+"/v1/workflow-templates/a/publish",[
  "Content-Type","application/json",
  "Authorization","Bearer first",
  "authorization","Bearer second"
 ]);
 assert.equal(response.status,400);
 assert.deepEqual(response.body,{error:"DUPLICATE_HEADER"});
}));
