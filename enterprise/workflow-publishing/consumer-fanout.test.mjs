import test from "node:test";
import assert from "node:assert/strict";
import {fanoutCommittedEvent} from "./consumer-fanout.mjs";
const event={tenantID:"tenant-a",eventID:"a".repeat(64),workItemID:"job-a",revision:1,action:"approve",type:"workflow.work_item.transitioned"};
const registrations=["enforcer","accounting"].map(consumerID=>({tenantID:"tenant-a",consumerID,enabled:true,eventTypes:[event.type],allowedActions:["approve"]}));
function fixture(committed=true){
 const keys=new Set();let calls=0;
 return {keys,get calls(){return calls},store:{transaction:async(_tenant,_event,fn)=>{
  const staged=new Set(keys);
  const response=await fn({verifyCommittedEvent:async()=>committed,insertDeliveryIfAbsent:async x=>{
   calls++;const key=x.tenantID+"|"+x.eventID+"|"+x.consumerID;
   if(staged.has(key))return false;staged.add(key);return true;
  }});
  keys.clear();for(const key of staged)keys.add(key);
  return response;
 }}};
}
test("fanout creates one independent delivery for each matching consumer",async()=>{
 const f=fixture();const result=await fanoutCommittedEvent({event,registrations,store:f.store});
 assert.deepEqual(result,{tenantID:"tenant-a",eventID:event.eventID,eligible:2,inserted:2});assert.equal(f.keys.size,2);
});
test("retry is idempotent and does not duplicate consumer rows",async()=>{
 const f=fixture();
 await fanoutCommittedEvent({event,registrations,store:f.store});
 const next=await fanoutCommittedEvent({event,registrations,store:f.store});
 assert.equal(next.inserted,0);assert.equal(f.keys.size,2);
});
test("non-committed events are rejected without fanout writes",async()=>{
 const f=fixture(false);
 await assert.rejects(()=>fanoutCommittedEvent({event,registrations,store:f.store}),/EVENT_NOT_COMMITTED/);
 assert.equal(f.calls,0);
});
test("other-tenant registrations cannot be routed",async()=>{
 const f=fixture();
 const result=await fanoutCommittedEvent({event,registrations:[...registrations,{...registrations[0],tenantID:"tenant-b",consumerID:"other"}],store:f.store});
 assert.equal(result.inserted,2);assert.equal(f.keys.size,2);
});
