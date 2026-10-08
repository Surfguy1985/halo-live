import test from "node:test";
import assert from "node:assert/strict";
import {createTrustedSessionResolver,createAuthenticatedWorkflowGateway} from "./trusted-auth.mjs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";
const verified={subject:"worker-123"};
const membership={active:true,tenantID:"tenant-a",industryIDs:["construction"],permissions:["workflow:publish"]};
const resolver=(record=membership)=>createTrustedSessionResolver({
 verifyBearer:async token=>token==="valid-token"?verified:null,
 loadMembership:async subject=>subject==="worker-123"?record:null
});
const request=(token="valid-token")=>({method:"POST",path:"/v1/workflow-templates/example/publish",
 headers:{"authorization":"Bearer "+token,"content-type":"application/json","idempotency-key":"id-1"},
 body:JSON.stringify({requestID:"id-1",expectedRevision:0,
 layout:{schemaVersion:1,templateID:"example",templateVersion:1,tenantID:"tenant-a",
 industryID:"construction",blocks:[]}})});
test("missing and invalid bearer credentials rejected",async()=>{
 const handler=createAuthenticatedWorkflowGateway({resolveSession:resolver(),
 publishHandler:async()=>{throw Error("should not publish");}});
 assert.equal((await handler({...request(),headers:{}})).status,401);
 assert.equal((await handler(request("invalid"))).status,401);
});
test("membership is server-owned and disabled users denied",async()=>{
 const gateway=createAuthenticatedWorkflowGateway({resolveSession:resolver({...membership,active:false}),
 publishHandler:async()=>{throw Error("should not publish");}});
 assert.equal((await gateway(request())).status,403);
});
test("trusted identity, membership and permissions reach publisher",async()=>{
 let captured;
 const publisher={publish:async args=>{captured=args;return {revision:1}}};
 const gateway=createAuthenticatedWorkflowGateway({resolveSession:resolver(),
 publishHandler:createWorkflowPublishHandler({publisher,enabled:true})});
 const r=await gateway(request());
 assert.equal(r.status,200);
 assert.equal(captured.session.actorID,"worker-123");
 assert.equal(captured.session.tenantID,"tenant-a");
 assert.ok(Object.isFrozen(captured.session));
});
test("forged tenant in payload rejected by domain, never passed as authority",async()=>{
 const publisher={publish:async args=>{
 if(args.proposal.layout.tenantID!==args.session.tenantID) {
   const {PublishError}=await import("./publisher.mjs");
   throw new PublishError("FORBIDDEN","mismatch");
 }
 }};
 const gateway=createAuthenticatedWorkflowGateway({resolveSession:resolver(),
 publishHandler:createWorkflowPublishHandler({publisher,enabled:true})});
 const r=request();const body=JSON.parse(r.body);body.layout.tenantID="tenant-b";r.body=JSON.stringify(body);
 assert.equal((await gateway(r)).status,403);
});
