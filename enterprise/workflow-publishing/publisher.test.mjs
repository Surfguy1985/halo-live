import test from "node:test";
import assert from "node:assert/strict";
import { WorkflowTemplatePublisher, PublishError } from "./publisher.mjs";

const layout = () => ({
  schemaVersion: 1, templateID: "example", templateVersion: 1,
  tenantID: "alpha", industryID: "construction",
  blocks: [{id:"assign", kind:"assignment", title:"Assign", order:0, required:true,
    visibleToRoles:["manager"], config:{}}]
});
const session = () => ({authenticated:true, tenantID:"alpha", actorID:"admin",
  permissions:["workflow:publish"], industryIDs:["construction"]});
const proposal = () => ({expectedRevision:0, layout:layout()});
function store() {
  const state={template:null, keys:new Map(), audits:[]};
  return {state, transaction:async (_tenant,_id,fn) => {
    // Single-threaded test double only; NOT a concurrency-safe production store.
    const pending={template:state.template,keys:new Map(state.keys),audits:[...state.audits]};
    const tx={
      getIdempotency: async k => pending.keys.get(k),
      getTemplate: async () => pending.template,
      saveTemplate: async v => {pending.template=v;},
      appendAudit: async v => {pending.audits.push(v);},
      saveIdempotency: async (k,v) => {pending.keys.set(k,v);}
    };
    const result=await fn(tx);
    state.template=pending.template;state.keys=pending.keys;state.audits=pending.audits;
    return result;
  }};
}
async function rejects(fn,code){await assert.rejects(fn,e => e instanceof PublishError && e.code === code);}
test("publishes once and records revision and audit",async()=>{
  const db=store(), service=new WorkflowTemplatePublisher(db);
  const r=await service.publish({session:session(),templateID:"example",idempotencyKey:"k1",proposal:proposal()});
  assert.equal(r.revision,1);assert.equal(db.state.audits.length,1);
  assert.equal(db.state.audits[0].actorID,"admin");
});
test("identical retry returns result without another audit",async()=>{
  const db=store(), service=new WorkflowTemplatePublisher(db), p=proposal();
  const input={session:session(),templateID:"example",idempotencyKey:"k1",proposal:p};
  assert.deepEqual(await service.publish(input),await service.publish(input));
  assert.equal(db.state.audits.length,1);
});
test("idempotency key cannot be reused for changed payload",async()=>{
  const service=new WorkflowTemplatePublisher(store()), p=proposal();
  await service.publish({session:session(),templateID:"example",idempotencyKey:"k1",proposal:p});
  await rejects(()=>service.publish({session:session(),templateID:"example",idempotencyKey:"k1",
    proposal:{...p,expectedRevision:1}}),"IDEMPOTENCY_CONFLICT");
});
test("stale expected revision rejected",async()=>{
  const service=new WorkflowTemplatePublisher(store());
  await service.publish({session:session(),templateID:"example",idempotencyKey:"k1",proposal:proposal()});
  await rejects(()=>service.publish({session:session(),templateID:"example",idempotencyKey:"k2",proposal:proposal()}),"REVISION_CONFLICT");
});
test("unauthorized and cross-tenant publishing denied",async()=>{
  const service=new WorkflowTemplatePublisher(store());
  await rejects(()=>service.publish({session:{...session(),permissions:[]},templateID:"example",
    idempotencyKey:"x",proposal:proposal()}),"FORBIDDEN");
  await rejects(()=>service.publish({session:{...session(),tenantID:"other"},templateID:"example",
    idempotencyKey:"y",proposal:proposal()}),"FORBIDDEN");
  await rejects(()=>service.publish({session:{...session(),industryIDs:[]},templateID:"example",
    idempotencyKey:"z",proposal:proposal()}),"FORBIDDEN");
});
test("invalid block and missing revision are rejected",async()=>{
  const service=new WorkflowTemplatePublisher(store()), p=proposal();
  p.layout.blocks[0].kind="script";
  await rejects(()=>service.publish({session:session(),templateID:"example",idempotencyKey:"a",proposal:p}),"INVALID");
  await rejects(()=>service.publish({session:session(),templateID:"example",idempotencyKey:"b",
    proposal:{layout:layout()}}),"INVALID");
});
test("failed audit rolls back all writes in transactional adapter",async()=>{
  const base=store(), original=base.transaction;
  base.transaction=(tenant,id,fn)=>original(tenant,id,async tx=>{
    tx.appendAudit=async()=>{throw Error("audit unavailable");};
    return fn(tx);
  });
  await assert.rejects(()=>new WorkflowTemplatePublisher(base).publish({
    session:session(),templateID:"example",idempotencyKey:"k",proposal:proposal()}));
  assert.equal(base.state.template,null);assert.equal(base.state.keys.size,0);
});

test("rejects revisions whose next value cannot be represented safely",async()=>{
 const db=store(),service=new WorkflowTemplatePublisher(db);
 for(const revision of [Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER+1]){
  await rejects(()=>service.publish({session:session(),templateID:"example",
   idempotencyKey:"overflow-"+revision,
   proposal:{...proposal(),expectedRevision:revision}}),"INVALID");
 }
 assert.equal(db.state.template,null);
 assert.equal(db.state.audits.length,0);
 assert.equal(db.state.keys.size,0);
});
test("last safe next revision publishes and idempotently replays once",async()=>{
 const db=store(),service=new WorkflowTemplatePublisher(db);
 const current=Number.MAX_SAFE_INTEGER-1;
 db.state.template={...layout(),revision:current};
 const input={session:session(),templateID:"example",idempotencyKey:"last-safe",
  proposal:{...proposal(),expectedRevision:current}};
 const result=await service.publish(input);
 assert.equal(result.revision,Number.MAX_SAFE_INTEGER);
 assert.deepEqual(await service.publish(input),result);
 assert.equal(db.state.audits.length,1);
});
