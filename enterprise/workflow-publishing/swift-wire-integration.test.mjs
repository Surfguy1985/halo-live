import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";
import {validateLayoutV1} from "./layout-contract.mjs";

const fixturePath=process.env.HALO_SWIFT_WIRE_FIXTURE;
if (!fixturePath) throw new Error("HALO_SWIFT_WIRE_FIXTURE required: this test must consume JSONEncoder output from compiled Swift");
const raw=readFileSync(fixturePath);
const proposal=JSON.parse(raw.toString("utf8"));
const session=Object.freeze({
 authenticated:true, actorID:"staging-admin", tenantID:"staging-tenant",
 industryIDs:["construction"], permissions:["workflow:publish"]
});

function isolatedStore() {
 const state={template:null,keys:new Map(),audits:[]};
 return {
  state,
  async transaction(_tenant,_templateID,callback) {
   const next={template:state.template,keys:new Map(state.keys),audits:[...state.audits]};
   const tx={
    getIdempotency:async key=>next.keys.get(key),
    getTemplate:async()=>next.template,
    saveTemplate:async value=>{next.template=value;},
    saveIdempotency:async(key,value)=>{next.keys.set(key,value);},
    appendAudit:async value=>{next.audits.push(value);}
   };
   const result=await callback(tx);
   state.template=next.template;state.keys=next.keys;state.audits=next.audits;
   return result;
  }
 };
}
const request=(body=raw,key=proposal.requestID)=>({
 method:"POST",path:"/v1/workflow-templates/construction-dispatch/publish",
 headers:{"content-type":"application/json","idempotency-key":key},body
});

test("compiled Swift JSONEncoder proposal satisfies authoritative Node layout contract",()=>{
 assert.equal(proposal.layout.templateID,"construction-dispatch");
 assert.equal(proposal.layout.blocks.length,2);
 assert.equal(proposal.expectedRevision,0);
 assert.equal(typeof proposal.requestID,"string");
 assert.equal(validateLayoutV1(proposal.layout),true);
});

test("Swift wire payload publishes through real Node handler and publisher with audit and idempotency",async()=>{
 const store=isolatedStore();
 const handler=createWorkflowPublishHandler({enabled:true,publisher:new WorkflowTemplatePublisher(store)});
 const first=await handler(request(),session);
 assert.equal(first.status,200,first.body);
 assert.deepEqual(JSON.parse(first.body),{templateID:"construction-dispatch",revision:1,templateVersion:1});
 assert.equal(store.state.audits.length,1);
 const replay=await handler(request(),session);
 assert.equal(replay.status,200);
 assert.deepEqual(JSON.parse(replay.body),JSON.parse(first.body));
 assert.equal(store.state.audits.length,1,"idempotent replay must not duplicate audit");
 const stale=await handler(request(raw,"new-request-id"),session);
 assert.equal(stale.status,422,"header and body idempotency mismatch must fail before storage");
 const changed=Buffer.from(JSON.stringify({...proposal,requestID:"new-request-id"}));
 const conflict=await handler(request(changed,"new-request-id"),session);
 assert.equal(conflict.status,409);
 assert.deepEqual(JSON.parse(conflict.body),{error:"REVISION_CONFLICT"});
});

test("Swift proposal cannot override server-side tenant or permissions",async()=>{
 const handler=createWorkflowPublishHandler({enabled:true,publisher:new WorkflowTemplatePublisher(isolatedStore())});
 const denied=await handler(request(),{...session,tenantID:"another-tenant"});
 assert.equal(denied.status,403);
 const noPermission=await handler(request(),{...session,permissions:[]});
 assert.equal(noPermission.status,403);
});
