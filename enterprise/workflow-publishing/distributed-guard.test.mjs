import test from "node:test";
import assert from "node:assert/strict";
import {createDistributedRequestGuard} from "./distributed-guard.mjs";
test("shared Redis counter limits across separate server instances",async()=>{
 const counters=new Map();
 const redis={eval:async(_script,{keys})=>{
  const key=keys[0],next=(counters.get(key)||0)+1;counters.set(key,next);return next;
 }};
 const gate=async()=>({status:200,body:"{}"});
 const a=createDistributedRequestGuard({gateway:gate,redis,limit:2,clock:()=>10000});
 const b=createDistributedRequestGuard({gateway:gate,redis,limit:2,clock:()=>10000});
 const req={peerAddress:"127.0.0.1"};
 assert.equal((await a(req)).status,200);
 assert.equal((await b(req)).status,200);
 assert.equal((await a(req)).status,429);
});
test("fails closed if Redis is unavailable",async()=>{
 const guard=createDistributedRequestGuard({gateway:async()=>({status:200}),redis:{eval:async()=>{throw Error("offline")}}});
 assert.equal((await guard({peerAddress:"127.0.0.1"})).status,503);
});
