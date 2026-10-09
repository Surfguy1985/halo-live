import test from "node:test";
import assert from "node:assert/strict";
import {createStageTracer} from "./stage-tracer.mjs";
test("records named stage duration and correlation safely",async()=>{
 let now=0;const events=[];
 const trace=createStageTracer({clock:()=>now,emit:e=>events.push(e)});
 const result=await trace("membership.load","request-1",async()=>{now=42;return {active:true}});
 assert.deepEqual(result,{active:true});
 assert.equal(events[0].durationMs,42);
 assert.equal(events[0].correlationID,"request-1");
});
test("records failures without changing exceptions",async()=>{
 const events=[],trace=createStageTracer({emit:e=>events.push(e)});
 await assert.rejects(()=>trace("workflow.publish","req",async()=>{throw Error("private")}),/private/);
 assert.equal(events[0].outcome,"error");
 assert.ok(!JSON.stringify(events).includes("private"));
});
