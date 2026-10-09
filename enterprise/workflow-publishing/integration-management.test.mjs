import test from "node:test";
import assert from "node:assert/strict";
import {IntegrationManagementService} from "./integration-management.mjs";
import {RegistryError} from "./integration-registry.mjs";
const session={authenticated:true,actorID:"owner-a",tenantID:"tenant-a",permissions:["integrations:manage"]};
const input={session,tenantID:"tenant-a",consumerID:"enforcer",expectedRevision:0,requestID:"req-a",
 subscription:{enabled:true,eventTypes:["workflow.work_item.transitioned"],allowedActions:["approve"]}};
function memory(fail=false){
 const state={registration:null,receipts:new Map(),audit:[]};
 return {state,transaction:async(_tenant,_consumer,fn)=>{
  const snapshot={registration:state.registration,receipts:new Map(state.receipts),audit:[...state.audit]};
  const result=await fn({
   getReceipt:async key=>snapshot.receipts.get(key),
   getLockedRegistration:async()=>snapshot.registration,
   upsertRegistration:async record=>{snapshot.registration=record;},
   appendAudit:async event=>{if(fail)throw Error("audit fails");snapshot.audit.push(event);},
   saveReceipt:async(key,value)=>{snapshot.receipts.set(key,value);}
  });
  Object.assign(state,snapshot);return result;
 }};
}
test("registration update commits one revision and audit",async()=>{
 const db=memory();const r=await new IntegrationManagementService(db).update(input);
 assert.equal(r.revision,1);assert.equal(db.state.audit.length,1);assert.equal(db.state.registration.enabled,true);
});
test("matching replay returns receipt without a second audit",async()=>{
 const db=memory(),svc=new IntegrationManagementService(db);
 assert.deepEqual(await svc.update(input),await svc.update(input));assert.equal(db.state.audit.length,1);
});
test("stale revision, same-key mutation and wrong-tenant requests fail closed",async()=>{
 const db=memory(),svc=new IntegrationManagementService(db);await svc.update(input);
 await assert.rejects(()=>svc.update({...input,requestID:"different"}),e=>e.code==="REVISION_CONFLICT");
 await assert.rejects(()=>svc.update({...input,subscription:{...input.subscription,enabled:false}}),e=>e.code==="IDEMPOTENCY_CONFLICT");
 await assert.rejects(()=>svc.update({...input,tenantID:"tenant-b"}),e=>e.code==="FORBIDDEN_SCOPE");
});
test("audit write failure rolls back subscription and receipt",async()=>{
 const db=memory(true);await assert.rejects(()=>new IntegrationManagementService(db).update(input));
 assert.equal(db.state.registration,null);assert.equal(db.state.audit.length,0);assert.equal(db.state.receipts.size,0);
});
test("explicit disable increments revision and records revocation",async()=>{
 const db=memory(),svc=new IntegrationManagementService(db);await svc.update(input);
 const r=await svc.update({...input,requestID:"req-b",expectedRevision:1,
 subscription:{enabled:false,eventTypes:[],allowedActions:[]}});
 assert.equal(r.enabled,false);assert.equal(r.revision,2);
 assert.equal(db.state.audit[1].action,"integration.revoked");
});
