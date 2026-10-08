import test from "node:test";
import assert from "node:assert/strict";
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
