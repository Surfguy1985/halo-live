import test from "node:test";
import assert from "node:assert/strict";
import {createOutboxWorker} from "./outbox-worker.mjs";
function fixture(event){
 const calls=[];let next=event;
 const store={
  claim:async()=>{const result=next;next=null;return result;},
  complete:async x=>{calls.push(["complete",x]);return true;},
  retry:async x=>{calls.push(["retry",x]);return true;},
  deadLetter:async x=>{calls.push(["deadLetter",x]);return true;}
 };
 return {store,calls};
}
const event={eventID:"a".repeat(64),tenantID:"tenant-a",workItemID:"job-a",revision:2,action:"assign",attempts:1,leaseToken:"lease-1"};
const make=(fixture,deliver,maxAttempts=8)=>createOutboxWorker({store:fixture.store,deliver,consumerID:"enforcer-adapter",workerID:"worker-1",clock:()=>1000,maxAttempts});
test("idle worker does not invoke delivery",async()=>{
 const f=fixture(null);let called=0;const result=await make(f,async()=>called++).tick();
 assert.equal(result.status,"idle");assert.equal(called,0);
});
test("success finalizes lease exactly once",async()=>{
 const f=fixture(event);let delivered;
 const result=await make(f,async x=>{delivered=x;}).tick();
 assert.equal(result.status,"delivered");assert.equal(delivered.eventID,event.eventID);
 assert.equal(f.calls[0][0],"complete");assert.equal(f.calls.length,1);
});
test("temporary failure schedules bounded retry",async()=>{
 const f=fixture({...event,attempts:3});
 const result=await make(f,async()=>{throw Error("timeout");}).tick();
 assert.deepEqual({status:result.status,delayMs:result.delayMs},{status:"retry_scheduled",delayMs:4000});
 assert.equal(f.calls[0][0],"retry");assert.equal(f.calls[0][1].availableAt,5000);
});
test("exhausted failure routes to dead letter",async()=>{
 const f=fixture({...event,attempts:8});
 const result=await make(f,async()=>{throw Object.assign(Error("bad"),{code:"UPSTREAM_REJECTED"});}).tick();
 assert.equal(result.status,"dead_letter");assert.equal(f.calls[0][1].errorCode,"UPSTREAM_REJECTED");
});
test("expired fencing token rejects stale completion",async()=>{
 const f=fixture(event);f.store.complete=async()=>false;
 const result=await make(f,async()=>{}).tick();
 assert.equal(result.status,"lease_lost");
});
