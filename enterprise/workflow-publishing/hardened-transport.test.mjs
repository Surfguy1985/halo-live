import test from "node:test";
import assert from "node:assert/strict";
import {createHardenedTransport,classifyDeliveryStatus,TransportError} from "./hardened-transport.mjs";
const envelope={url:"https://hooks.example.com/halo",body:"{}",headers:{"x-halo-signature":"v1=abc"}};
test("rejects ordinary fetch and unverified egress adapters",()=>{
 assert.throws(()=>createHardenedTransport({egressClient:{send:async()=>({status:200,responseBytes:0})}}),TransportError);
});
test("passes strict transport limits and no-redirect requirement",async()=>{
 let called;const transport=createHardenedTransport({egressClient:{hardened:true,send:async req=>{called=req;return {status:204,responseBytes:0};}}});
 assert.deepEqual(await transport.deliver(envelope),{status:"delivered",httpStatus:204});
 assert.equal(called.followRedirects,false);assert.equal(called.timeoutMs,5000);
});
test("non-success status classified into retry or permanent",async()=>{
 for(const status of [408,425,429,500,503]){
  const t=createHardenedTransport({egressClient:{hardened:true,send:async()=>({status,responseBytes:0})}});
  await assert.rejects(()=>t.deliver(envelope),e=>e.code==="UPSTREAM_RETRYABLE");
 }
 for(const status of [301,302,400,401,403,404]){
  const t=createHardenedTransport({egressClient:{hardened:true,send:async()=>({status,responseBytes:0})}});
  await assert.rejects(()=>t.deliver(envelope),e=>e.code==="UPSTREAM_PERMANENT");
 }
 assert.equal(classifyDeliveryStatus(200),"delivered");
});
test("rejects oversized response and unsafe limits",async()=>{
 const t=createHardenedTransport({egressClient:{hardened:true,send:async()=>({status:200,responseBytes:20000})}});
 await assert.rejects(()=>t.deliver(envelope),e=>e.code==="EGRESS_POLICY_VIOLATION");
 assert.throws(()=>createHardenedTransport({egressClient:{hardened:true,send:async()=>{}},timeoutMs:99999}),TransportError);
});
