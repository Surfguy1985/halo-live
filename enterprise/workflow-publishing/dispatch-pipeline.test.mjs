import test from "node:test";
import assert from "node:assert/strict";
import {createDispatchPipeline} from "./dispatch-pipeline.mjs";
const delivery={tenantID:"tenant-a",consumerID:"enforcer",eventID:"a".repeat(64),workItemID:"job-a",revision:2,action:"approve",type:"workflow.work_item.transitioned"};
const permit={permitID:"permit-a",registrationRevision:3};
function fixture({enabled=true,lease=true,registered=true,permitAccepted=true}={}){
 const calls=[];
 const pipeline=()=>createDispatchPipeline({enabled,allowedHosts:["hooks.example.com"],
  registry:{lookup:async()=>{calls.push("registry");return {tenantID:delivery.tenantID,consumerID:delivery.consumerID,enabled:registered,revision:3,eventTypes:[delivery.type],allowedActions:[delivery.action]};}},
  leaseVerifier:{verify:async()=>{calls.push("lease");return lease;}},
  permitGateway:{authorizeSend:async()=>{calls.push("permit");if(!permitAccepted)throw Error("denied");}},
  secretProvider:{get:async()=>{calls.push("secret");return {secret:Buffer.alloc(32,2),keyID:"key-a",destinationURL:"https://hooks.example.com/event"};}},
  egressClient:{hardened:true,send:async req=>{calls.push("egress");assert.equal(req.followRedirects,false);return {status:204,responseBytes:0};}}
 });
 return {pipeline,calls};
}
test("disabled by default refuses to construct network-capable pipeline",()=>{
 assert.throws(()=>createDispatchPipeline({}),e=>e.code==="DISPATCH_DISABLED");
});
test("approved delivery follows lease registry permit secret egress sequence",async()=>{
 const x=fixture();const result=await x.pipeline().deliver({delivery,permit,now:1700000000000});
 assert.equal(result.status,"delivered");
 assert.deepEqual(x.calls,["lease","registry","permit","secret","egress"]);
});
test("invalid lease, revoked registration and permit failure never send",async()=>{
 for(const config of [{lease:false},{registered:false},{permitAccepted:false}]){
  const x=fixture(config);
  await assert.rejects(()=>x.pipeline().deliver({delivery,permit,now:1700000000000}));
  assert.ok(!x.calls.includes("egress"));
 }
});
test("mismatched registration revision denies before secret or send",async()=>{
 const x=fixture();
 await assert.rejects(()=>x.pipeline().deliver({delivery,permit:{...permit,registrationRevision:2},now:1700000000000}),
  e=>e.code==="REGISTRATION_CHANGED");
 assert.ok(!x.calls.includes("secret"));
});
