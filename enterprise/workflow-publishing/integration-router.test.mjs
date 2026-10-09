import test from "node:test";
import assert from "node:assert/strict";
import {planIntegrationDelivery as plan} from "./integration-router.mjs";
const event={eventID:"a".repeat(64),tenantID:"tenant-a",workItemID:"job-a",type:"workflow.work_item.transitioned",revision:1,action:"approve"};
const reg=(consumerID,tenantID="tenant-a")=>({consumerID,tenantID,enabled:true,eventTypes:["workflow.work_item.transitioned"],allowedActions:["approve"]});
test("routes only subscribed tenant and action",()=>{
 const out=plan({event,registrations:[reg("enforcer"),reg("tenant-b-consumer","tenant-b"),reg("disabled"),{...reg("wrong-action"),allowedActions:["assign"]}] .map(x=>x.consumerID==="disabled"?{...x,enabled:false}:x)});
 assert.deepEqual(out.map(x=>x.consumerID),["enforcer"]);
 assert.equal(out[0].deliveryKey,"enforcer:"+event.eventID);
});
test("rejects duplicate consumer IDs within one routed tenant",()=>{
 assert.throws(()=>plan({event,registrations:[reg("enforcer"),reg("enforcer")]}),/duplicate/);
});
test("invalid registrations and events fail closed",()=>{
 for(const registrations of [[{...reg("x"),tenantID:"bad/tenant"}],[{...reg("x"),eventTypes:["arbitrary"]}]]){
  assert.throws(()=>plan({event,registrations}),TypeError);
 }
 assert.throws(()=>plan({event:{...event,revision:-1},registrations:[]}),TypeError);
});
test("returns frozen, transport-free destination records",()=>{
 const out=plan({event,registrations:[reg("enforcer")]});
 assert.ok(Object.isFrozen(out));assert.ok(Object.isFrozen(out[0]));
 assert.deepEqual(Object.keys(out[0]),["tenantID","eventID","consumerID","deliveryKey"]);
});
