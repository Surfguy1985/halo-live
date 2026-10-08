import test from "node:test";
import assert from "node:assert/strict";
import {createWorkflowReadiness} from "./readiness.mjs";
test("requires healthy PostgreSQL and Redis",async()=>{
 const check=createWorkflowReadiness({postgres:{query:async()=>({rows:[{ready:1}]})},redis:{ping:async()=> "PONG"}});
 assert.equal(await check(),true);
});
test("fails closed on unavailable cache",async()=>{
 const check=createWorkflowReadiness({postgres:{query:async()=>({rows:[{ready:1}]})},redis:{ping:async()=>{throw Error("down")}}});
 assert.equal(await check(),false);
});
