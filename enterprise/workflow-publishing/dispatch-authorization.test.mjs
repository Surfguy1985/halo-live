import test from "node:test";
import assert from "node:assert/strict";
import {authorizeDeliveryNow as authorize} from "./dispatch-authorization.mjs";
const delivery={tenantID:"tenant-a",consumerID:"enforcer",eventID:"a".repeat(64),action:"approve",type:"workflow.work_item.transitioned"};
const registration={tenantID:"tenant-a",consumerID:"enforcer",enabled:true,revision:3,eventTypes:[delivery.type],allowedActions:["approve"]};
const check=(record,override={})=>authorize({delivery:{...delivery,...override},registry:{lookup:async()=>record}});
test("current enabled matching registration permits dispatch",async()=>assert.deepEqual(await check(registration),{authorized:true,registrationRevision:3}));
test("revoked, absent and wrong tenant registry fail closed",async()=>{
 for(const r of [null,{...registration,enabled:false},{...registration,tenantID:"tenant-b"}])
  assert.equal((await check(r)).authorized,false);
});
test("action and event subscription changes block pending deliveries",async()=>{
 assert.equal((await check({...registration,allowedActions:["close"]})).reason,"SUBSCRIPTION_DENIED");
 assert.equal((await check({...registration,eventTypes:[]})).reason,"SUBSCRIPTION_DENIED");
});
test("invalid delivery identity denies before registry access",async()=>{
 let calls=0;
 const result=await authorize({delivery:{...delivery,consumerID:"bad/name"},registry:{lookup:async()=>{calls++;return registration;}}});
 assert.equal(result.authorized,false);assert.equal(calls,0);
});
