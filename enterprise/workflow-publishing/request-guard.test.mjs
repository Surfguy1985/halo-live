import test from "node:test";
import assert from "node:assert/strict";
import {createRequestGuard} from "./request-guard.mjs";
test("rate limits per trusted peer address and resets at window boundary",async()=>{
 let now=1000,calls=0;
 const guard=createRequestGuard({gateway:async()=>{calls++;return {status:200,body:"{}"};},
  clock:()=>now,limit:2,windowMs:1000});
 const req={peerAddress:"127.0.0.1"};
 assert.equal((await guard(req)).status,200);
 assert.equal((await guard(req)).status,200);
 assert.equal((await guard(req)).status,429);
 assert.equal(calls,2);
 assert.equal((await guard({peerAddress:"127.0.0.2"})).status,200);
 now+=1000;
 assert.equal((await guard(req)).status,200);
});
test("missing trusted socket address rejected",async()=>{
 const guard=createRequestGuard({gateway:async()=>({status:200})});
 assert.equal((await guard({headers:{"x-forwarded-for":"fake"}})).status,400);
});
