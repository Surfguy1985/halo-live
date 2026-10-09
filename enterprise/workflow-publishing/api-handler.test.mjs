import test from "node:test";
import assert from "node:assert/strict";
import {createWorkflowPublishHandler} from "./api-handler.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";
const layout={schemaVersion:1,templateID:"example",templateVersion:1,tenantID:"alpha",
 industryID:"construction",blocks:[{id:"one",kind:"assignment",title:"Assign",order:0,
 required:true,visibleToRoles:["manager"],config:{}}]};
const session={authenticated:true,actorID:"user",tenantID:"alpha",
 permissions:["workflow:publish"],industryIDs:["construction"]};
const request=(key="same")=>({method:"POST",path:"/v1/workflow-templates/example/publish",
 headers:{"content-type":"application/json","idempotency-key":key},
 body:JSON.stringify({requestID:key,expectedRevision:0,layout})});
test("feature flag denies route",async()=>{
 const h=createWorkflowPublishHandler({publisher:{publish:()=>{throw Error("must not call");}}});
 assert.equal((await h(request(),session)).status,404);
});
test("unauthorized sessions fail before domain service call",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");}}});
 assert.equal((await h(request(),null)).status,403);
 assert.equal((await h(request(),{...session,permissions:[]})).status,403);
});
test("enforces idempotency header equality and request size",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");}}});
 const wrong=request();wrong.body=JSON.stringify({requestID:"other",expectedRevision:0,layout});
 assert.equal((await h(wrong,session)).status,422);
 const big=request();big.body="a".repeat(131073);
 assert.equal((await h(big,session)).status,413);
});
test("forwards only verified identity and normalized proposal",async()=>{
 let received;
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:async a=>{received=a;return {revision:1};}}});
 const response=await h(request(),session);
 assert.equal(response.status,200);
 assert.equal(received.session,session);
 assert.equal(received.templateID,"example");
 assert.deepEqual(JSON.parse(response.body),{revision:1});
});
test("redacts unexpected errors",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:async()=>{throw Error("private SQL detail");}}});
 const result=await h(request(),session);
 assert.equal(result.status,500);
 assert.ok(!result.body.includes("private SQL"));
});
