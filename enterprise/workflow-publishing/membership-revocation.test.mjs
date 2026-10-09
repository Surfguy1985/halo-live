import test from "node:test";
import assert from "node:assert/strict";
import {createTrustedSessionResolver,createAuthenticatedWorkflowGateway} from "./trusted-auth.mjs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";

const layout=()=>({schemaVersion:1,tenantID:"tenant-a",industryID:"construction",
 templateID:"work-order",templateVersion:1,blocks:[]});
const request=(key,body={})=>({method:"POST",path:"/v1/workflow-templates/work-order/publish",
 headers:{"authorization":"Bearer test-token","content-type":"application/json","idempotency-key":key},
 body:JSON.stringify({requestID:key,expectedRevision:0,layout:layout(),...body})});
function harness() {
 let membership={active:true,tenantID:"tenant-a",industryIDs:["construction"],permissions:["workflow:publish"]};
 let calls=0,commits=0;
 const store={transaction:async(_tenant,_template,fn)=>{
  const tx={getIdempotency:async()=>null,getTemplate:async()=>null,
   saveTemplate:async()=>{commits++;},saveIdempotency:async()=>{},appendAudit:async()=>{}};
  return fn(tx);
 }};
 const resolver=createTrustedSessionResolver({
  verifyBearer:async token=>token==="test-token"?{subject:"verified-actor"}:null,
  loadMembership:async subject=>subject==="verified-actor"?membership:null
 });
 const publisher=new WorkflowTemplatePublisher(store);
 const handler=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:async input=>{calls++;return publisher.publish(input);}
 }});
 const gateway=createAuthenticatedWorkflowGateway({resolveSession:resolver,publishHandler:handler});
 return {gateway,updateMembership:value=>{membership=value;},stats:()=>({calls,commits})};
}
test("membership revocation is checked on every request, not cached from prior publish",async()=>{
 const h=harness();
 assert.equal((await h.gateway(request("first"))).status,200);
 h.updateMembership({active:false,tenantID:"tenant-a",industryIDs:["construction"],permissions:["workflow:publish"]});
 assert.equal((await h.gateway(request("second"))).status,403);
 assert.deepEqual(h.stats(),{calls:1,commits:1});
});
test("untrusted body actor and permission fields cannot elevate a revoked account",async()=>{
 const h=harness();
 h.updateMembership({active:false,tenantID:"tenant-a",industryIDs:["construction"],permissions:["workflow:publish"]});
 const result=await h.gateway(request("forged",{actorID:"admin",permissions:["workflow:publish"],authenticated:true}));
 assert.equal(result.status,403);
 assert.deepEqual(h.stats(),{calls:0,commits:0});
});
test("membership scope, not body, governs tenant and industry publishing",async()=>{
 const h=harness();
 const tenant=await h.gateway(request("tenant-forged",{layout:{...layout(),tenantID:"tenant-b"}}));
 assert.equal(tenant.status,403);
 h.updateMembership({active:true,tenantID:"tenant-a",industryIDs:["property_management"],permissions:["workflow:publish"]});
 const industry=await h.gateway(request("industry-forged",{industryIDs:["construction"]}));
 assert.equal(industry.status,403);
 assert.deepEqual(h.stats(),{calls:2,commits:0});
});
test("missing publishing permission and invalid bearer fail before storage",async()=>{
 const h=harness();
 h.updateMembership({active:true,tenantID:"tenant-a",industryIDs:["construction"],permissions:[]});
 assert.equal((await h.gateway(request("no-permission"))).status,403);
 const invalid=request("invalid-token");
 invalid.headers.authorization="Bearer invalid";
 assert.equal((await h.gateway(invalid)).status,401);
 assert.deepEqual(h.stats(),{calls:0,commits:0});
});
