import test from "node:test";
import assert from "node:assert/strict";
import {createHmac} from "node:crypto";
import {buildSignedDelivery,requireApprovedDestination,DispatchEnvelopeError} from "./signed-dispatch-envelope.mjs";
const event={eventID:"a".repeat(64),tenantID:"tenant-a",workItemID:"job-a",revision:4,action:"approve",type:"workflow.work_item.transitioned"};
const base={event,consumerID:"enforcer",destinationURL:"https://hooks.example.com/halo",allowedHosts:["hooks.example.com"],secret:Buffer.alloc(32,7),keyID:"key-one",issuedAt:1700000000000,nonce:"nonce-one"};
test("constructs signed, stable, transport-free envelope",()=>{
 const out=buildSignedDelivery(base);
 assert.equal(out.url,"https://hooks.example.com/halo");
 assert.equal(out.headers["x-halo-signature"],"v1="+createHmac("sha256",base.secret).update(out.body).digest("hex"));
 assert.equal(JSON.parse(out.body).nonce,"nonce-one");
 assert.ok(Object.isFrozen(out.headers));
});
test("rejects invalid destinations, scheme, credentials and lookalike hostnames",()=>{
 for(const destinationURL of ["http://hooks.example.com/halo","https://evil.example.com/halo","https://hooks.example.com.evil.com/halo",
 "https://user:pass@hooks.example.com/halo","https://hooks.example.com:8443/halo",
 "https://hooks.example.com/halo#fragment","https://localhost/halo","https://127.0.0.1/halo"]){
  assert.throws(()=>requireApprovedDestination(destinationURL,base.allowedHosts),DispatchEnvelopeError,destinationURL);
 }
});
test("rejects short secrets and malformed delivery metadata",()=>{
 for(const overrides of [{secret:Buffer.alloc(8)},{event:{...event,revision:-1}},{consumerID:"../outside"},{keyID:"bad/key"}])
  assert.throws(()=>buildSignedDelivery({...base,...overrides}),DispatchEnvelopeError);
});
test("changing event payload or nonce produces distinct MAC",()=>{
 const a=buildSignedDelivery(base);
 const b=buildSignedDelivery({...base,nonce:"nonce-two"});
 const c=buildSignedDelivery({...base,event:{...event,action:"close"}});
 assert.notEqual(a.headers["x-halo-signature"],b.headers["x-halo-signature"]);
 assert.notEqual(a.headers["x-halo-signature"],c.headers["x-halo-signature"]);
});
