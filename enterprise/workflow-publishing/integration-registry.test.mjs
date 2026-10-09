import test from "node:test";
import assert from "node:assert/strict";
import {authorizeRegistryChange as authorize,RegistryError} from "./integration-registry.mjs";
const session={authenticated:true,actorID:"owner-a",tenantID:"tenant-a",permissions:["integrations:manage"]};
const input={session,tenantID:"tenant-a",consumerID:"enforcer",expectedRevision:0,
 subscription:{enabled:true,eventTypes:["workflow.work_item.transitioned"],allowedActions:["approve","close"]}};
test("permits explicitly scoped manager and returns immutable reviewed proposal",()=>{
 const result=authorize(input);assert.equal(result.actorID,"owner-a");
 assert.ok(Object.isFrozen(result.subscription.allowedActions));
});
test("rejects cross tenant access and unverified permissions",()=>{
 for(const changes of [{tenantID:"tenant-b"},{session:{...session,authenticated:false}},
 {session:{...session,permissions:[]}},{session:{...session,tenantID:"tenant-b"}}])
 assert.throws(()=>authorize({...input,...changes}),RegistryError);
});
test("requires safe revision and fixed subscription vocabulary",()=>{
 for(const bad of [-1,1.5,Number.MAX_SAFE_INTEGER+1])
  assert.throws(()=>authorize({...input,expectedRevision:bad}),RegistryError);
 for(const sub of [{...input.subscription,secret:"plaintext"},{...input.subscription,eventTypes:["other"]},
 {...input.subscription,allowedActions:["approve","approve"]}])
  assert.throws(()=>authorize({...input,subscription:sub}),RegistryError);
});
test("supports explicit revocation without deleting historical records",()=>{
 const result=authorize({...input,expectedRevision:5,subscription:{enabled:false,eventTypes:[],allowedActions:[]}});
 assert.equal(result.subscription.enabled,false);assert.equal(result.expectedRevision,5);
});
