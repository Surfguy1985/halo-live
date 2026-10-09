import test from "node:test";
import assert from "node:assert/strict";
import {FencedDispatchCoordinator} from "./dispatch-fencing.mjs";
const delivery={tenantID:"tenant-a",consumerID:"enforcer",eventID:"a".repeat(64),action:"approve",type:"workflow.work_item.transitioned"};
const current={tenantID:"tenant-a",consumerID:"enforcer",enabled:true,revision:2,eventTypes:[delivery.type],allowedActions:[delivery.action]};
const setup=()=>{
 let record={...current},invalidated=false;
 const registry={lookup:async()=>record};
 const permits={issue:async({registrationRevision})=>({permitID:"permit-a",registrationRevision}),
  validate:async()=>!invalidated,
  invalidateConsumer:async()=>{invalidated=true;return true;}};
 return {engine:new FencedDispatchCoordinator({registry,permits}),setRecord:x=>{record=x;}};
};
test("issue and validate only at current registration revision",async()=>{
 const {engine}=setup(),permit=await engine.issue(delivery);
 assert.equal(await engine.validateForSend({delivery,permit}),true);
});
test("revision rotation invalidates old permission",async()=>{
 const x=setup(),permit=await x.engine.issue(delivery);
 x.setRecord({...current,revision:3});
 assert.equal(await x.engine.validateForSend({delivery,permit}),false);
});
test("revocation prevents fresh permits and existing validations",async()=>{
 const x=setup(),permit=await x.engine.issue(delivery);
 x.setRecord({...current,enabled:false,revision:3});
 await x.engine.revoke({tenantID:"tenant-a",consumerID:"enforcer",revision:3});
 assert.equal(await x.engine.validateForSend({delivery,permit}),false);
 await assert.rejects(()=>x.engine.issue(delivery),e=>e.code==="REVOKED_OR_MISSING");
});
test("malformed permit denied",async()=>{
 const {engine}=setup();assert.equal(await engine.validateForSend({delivery,permit:{permitID:"bad/id"}}),false);
});
