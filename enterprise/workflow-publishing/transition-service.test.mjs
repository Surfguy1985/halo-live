import test from "node:test";
import assert from "node:assert/strict";
import {WorkflowTransitionService,TransitionError} from "./transition-service.mjs";
const session={authenticated:true,tenantID:"tenant-a",actorID:"manager-a",roles:["manager"],industryIDs:["construction"]};
const item=()=>({id:"job-a",tenantID:"tenant-a",industryID:"construction",templateID:"dispatch",templateVersion:1,state:"created",revision:0,assigneeID:"crew-a"});
const request=(key="req-a")=>({session,workItemID:"job-a",action:"assign",expectedRevision:0,idempotencyKey:key});
function memoryStore({failAt=null}={}){
 const state={item:item(),keys:new Map(),audits:[],outbox:[]};
 return {state,transaction:async (_tenant,_id,callback)=>{
   const draft={item:structuredClone(state.item),keys:new Map(state.keys),audits:[...state.audits],outbox:[...state.outbox]};
   const point=name=>{if(failAt===name)throw Error("forced "+name+" failure");};
   const tx={
    getIdempotency:async key=>draft.keys.get(key),
    getLockedWorkItem:async()=>draft.item,
    updateState:async ({expectedRevision,revision,state:next})=>{
      point("update");if(draft.item.revision!==expectedRevision)throw Error("CAS conflict");
      draft.item={...draft.item,state:next,revision};
    },
    appendAudit:async event=>{point("audit");draft.audits.push(event);},
    appendOutbox:async event=>{point("outbox");draft.outbox.push(event);},
    saveIdempotency:async (key,value)=>{point("receipt");draft.keys.set(key,value);}
   };
   const result=await callback(tx);
   Object.assign(state,draft);
   return result;
 }};
}
const fails=async(fn,code)=>assert.rejects(fn,e=>e instanceof TransitionError && e.code===code);
test("commits state, audit, outbox, idempotency in one logical transaction",async()=>{
 const store=memoryStore(),service=new WorkflowTransitionService(store);
 const result=await service.execute(request());
 assert.deepEqual(result,{workItemID:"job-a",tenantID:"tenant-a",state:"assigned",revision:1});
 assert.equal(store.state.item.revision,1);assert.equal(store.state.audits.length,1);
 assert.equal(store.state.outbox.length,1);assert.equal(store.state.keys.size,1);
});
test("identical retry returns receipt without duplicate side effects",async()=>{
 const store=memoryStore(),service=new WorkflowTransitionService(store);
 const first=await service.execute(request());
 const second=await service.execute(request());
 assert.deepEqual(first,second);
 assert.equal(store.state.audits.length,1);assert.equal(store.state.outbox.length,1);
});
test("changed payload with same key rejected even after state advances",async()=>{
 const service=new WorkflowTransitionService(memoryStore());
 await service.execute(request());
 await fails(()=>service.execute({...request(),action:"close"}),"IDEMPOTENCY_CONFLICT");
});
test("revision conflicts, tenant isolation and role failures do not write",async()=>{
 for(const change of [
  {expectedRevision:1},
  {session:{...session,tenantID:"tenant-b"}},
  {session:{...session,roles:["assignee"]}}
 ]){
  const store=memoryStore(),service=new WorkflowTransitionService(store);
  await assert.rejects(()=>service.execute({...request(),...change}));
  assert.equal(store.state.item.revision,0);assert.equal(store.state.audits.length,0);
 }
});
test("every injected persistence failure rolls back all logical writes",async()=>{
 for(const step of ["update","audit","outbox","receipt"]){
  const store=memoryStore({failAt:step}),service=new WorkflowTransitionService(store);
  await assert.rejects(()=>service.execute(request()));
  assert.deepEqual(store.state.item,item(),step);
  assert.equal(store.state.keys.size,0);assert.equal(store.state.audits.length,0);
  assert.equal(store.state.outbox.length,0);
 }
});
