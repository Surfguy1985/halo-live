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
test("handler construction fails fast without both publish and reconcile operations",()=>{
 assert.throws(()=>createWorkflowPublishHandler({publisher:{publish:async()=>{}}}),TypeError);
 assert.throws(()=>createWorkflowPublishHandler({publisher:{reconcile:async()=>{}}}),TypeError);
});
test("feature flag denies route",async()=>{
 const h=createWorkflowPublishHandler({publisher:{publish:()=>{throw Error("must not call");},reconcile:()=>{throw Error("must not call");}}});
 assert.equal((await h(request(),session)).status,404);
});
test("unauthorized sessions fail before domain service call",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");},reconcile:()=>{throw Error("must not call");}}});
 assert.equal((await h(request(),null)).status,403);
 assert.equal((await h(request(),{...session,permissions:[]})).status,403);
});
test("enforces idempotency header equality and request size",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");},reconcile:()=>{throw Error("must not call");}}});
 const wrong=request();wrong.body=JSON.stringify({requestID:"other",expectedRevision:0,layout});
 assert.equal((await h(wrong,session)).status,422);
 const big=request();big.body="a".repeat(131073);
 assert.equal((await h(big,session)).status,413);
});
test("forwards only verified identity and normalized proposal",async()=>{
 let received;
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:async a=>{received=a;return {revision:1};},reconcile:()=>{throw Error("must not call");}}});
 const response=await h(request(),session);
 assert.equal(response.status,200);
 assert.equal(received.session,session);
 assert.equal(received.templateID,"example");
 assert.deepEqual(JSON.parse(response.body),{revision:1});
});
test("redacts unexpected errors",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:async()=>{throw Error("private SQL detail");},reconcile:()=>{throw Error("must not call");}}});
 const result=await h(request(),session);
 assert.equal(result.status,500);
 assert.ok(!result.body.includes("private SQL"));
});

test("rejects negative, fractional, and unsafe revision numbers before publisher",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");},reconcile:()=>{throw Error("must not call");}}});
 for(const revision of [-1,-4,0.5,Number.MAX_SAFE_INTEGER+1]){
  const req=request("revision-check");
  req.body=JSON.stringify({requestID:"revision-check",expectedRevision:revision,layout});
  const response=await h(req,session);
  assert.equal(response.status,422);
  assert.deepEqual(JSON.parse(response.body),{error:"INVALID_REQUEST"});
 }
});

test("rejects next-revision overflow at HTTP boundary before publisher",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{publish:()=>{throw Error("must not call");},reconcile:()=>{throw Error("must not call");}}});
 for(const revision of [Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER+1]){
  const req=request("revision-overflow");
  req.body=JSON.stringify({requestID:"revision-overflow",expectedRevision:revision,layout});
  const response=await h(req,session);
  assert.equal(response.status,422);
  assert.deepEqual(JSON.parse(response.body),{error:"INVALID_REQUEST"});
 }
});

test("uncertain COMMIT returns explicit reconciliation signal without leaking SQL details",async()=>{
 const {WorkflowCommitUncertainError}=await import("./postgres-store.mjs");
 const h=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:async()=>{throw new WorkflowCommitUncertainError();},reconcile:()=>{throw Error("must not call");}
 }});
 const response=await h(request("uncertain-commit"),session);
 assert.equal(response.status,503);
 assert.deepEqual(JSON.parse(response.body),{error:"COMMIT_OUTCOME_UNKNOWN"});
 assert.equal(response.body.includes("SQL"),false);
});

const reconcileRequest=(key="original-request")=>({
 method:"POST",path:"/v1/workflow-templates/example/reconcile",
 headers:{"content-type":"application/json","idempotency-key":key},
 body:JSON.stringify({requestID:key,expectedRevision:0,layout})
});

test("reconcile route reads the original request receipt and never calls publish",async()=>{
 let received;
 const h=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:()=>{throw Error("must not replay publish");},
  reconcile:async input=>{received=input;return {requestID:input.idempotencyKey,
   outcome:"COMMITTED",result:{templateID:input.templateID,revision:1,templateVersion:1}};}
 }});
 const response=await h(reconcileRequest(),session);
 assert.equal(response.status,200);
 assert.equal(received.session,session);
 assert.equal(received.templateID,"example");
 assert.equal(received.idempotencyKey,"original-request");
 assert.deepEqual(received.proposal,{expectedRevision:0,layout});
 assert.deepEqual(JSON.parse(response.body),{requestID:"original-request",outcome:"COMMITTED",
  result:{templateID:"example",revision:1,templateVersion:1}});
});

test("reconcile route requires the exact original request ID and current authorization",async()=>{
 const h=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:()=>{throw Error("must not publish");},reconcile:()=>{throw Error("must not read");}
 }});
 const mismatch=reconcileRequest();mismatch.body=JSON.stringify({requestID:"other",expectedRevision:0,layout});
 assert.equal((await h(mismatch,session)).status,422);
 const extra=reconcileRequest();extra.body=JSON.stringify({requestID:"original-request",expectedRevision:0,layout,tenantID:"other"});
 assert.equal((await h(extra,session)).status,422);
 assert.equal((await h(reconcileRequest(),{...session,permissions:[]})).status,403);
 for(const revision of [-1,0.5,Number.MAX_SAFE_INTEGER]){
  const invalid=reconcileRequest();
  invalid.body=JSON.stringify({requestID:"original-request",expectedRevision:revision,layout});
  assert.equal((await h(invalid,session)).status,422);
 }
 const suffix=reconcileRequest();suffix.path+="/extra";
 assert.equal((await h(suffix,session)).status,404);
});

test("reconcile route returns stable not-found and redacted internal errors",async()=>{
 const {PublishError}=await import("./publisher.mjs");
 const notFound=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:()=>{},reconcile:async()=>{throw new PublishError("PUBLISH_REQUEST_NOT_FOUND","private");}
 }});
 const missing=await notFound(reconcileRequest(),session);
 assert.equal(missing.status,404);
 assert.deepEqual(JSON.parse(missing.body),{error:"PUBLISH_REQUEST_NOT_FOUND"});
 const broken=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:()=>{},reconcile:async()=>{throw Error("private SQL detail");}
 }});
 const failure=await broken(reconcileRequest(),session);
 assert.equal(failure.status,500);
 assert.deepEqual(JSON.parse(failure.body),{error:"INTERNAL"});
 assert.equal(failure.body.includes("SQL"),false);
});

test("reconcile route reports an altered original proposal as an idempotency conflict",async()=>{
 const {PublishError}=await import("./publisher.mjs");
 const h=createWorkflowPublishHandler({enabled:true,publisher:{
  publish:()=>{},reconcile:async()=>{throw new PublishError("IDEMPOTENCY_CONFLICT","private");}
 }});
 const response=await h(reconcileRequest(),session);
 assert.equal(response.status,409);
 assert.deepEqual(JSON.parse(response.body),{error:"IDEMPOTENCY_CONFLICT"});
});
