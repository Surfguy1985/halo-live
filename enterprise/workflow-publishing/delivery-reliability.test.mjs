import test from "node:test";
import assert from "node:assert/strict";
import {requireBoundLease,classifyObservedDelivery,recordDeliveryOutcome} from "./delivery-reliability.mjs";
const delivery={tenantID:"tenant-a",consumerID:"enforcer",eventID:"a".repeat(64)};
const lease={...delivery,workerID:"worker-a",leaseToken:"token-a"};
const permit={...delivery,permitID:"permit-a",registrationRevision:3,leaseToken:"token-a"};
test("permit is scoped to exact tenant, consumer, event and lease",()=>{
 assert.equal(requireBoundLease({delivery,lease,permit}).leaseToken,"token-a");
 for(const altered of [{...permit,leaseToken:"token-b"},{...permit,tenantID:"tenant-b"},{...permit,eventID:"b".repeat(64)}])
  assert.throws(()=>requireBoundLease({delivery,lease,permit:altered}),/LEASE_PERMIT_BINDING_DENIED/);
});
test("network failures and transient HTTP statuses are uncertain",()=>{
 assert.equal(classifyObservedDelivery({error:Error("timeout")}).state,"uncertain");
 for(const httpStatus of [408,425,429,500,502,503])
  assert.equal(classifyObservedDelivery({response:{httpStatus}}).state,"uncertain");
 assert.equal(classifyObservedDelivery({}).state,"uncertain");
});
test("explicit acknowledgment and permanent rejection are distinct",()=>{
 assert.equal(classifyObservedDelivery({response:{httpStatus:204}}).state,"acknowledged");
 assert.equal(classifyObservedDelivery({response:{httpStatus:400}}).state,"rejected");
});
test("durable outcome store receives fencing and rejects stale lease",async()=>{
 let captured;
 const accepted=await recordDeliveryOutcome({delivery,lease,permit,response:{httpStatus:202},
  store:{commitOutcome:async input=>{captured=input;return true;}}});
 assert.equal(accepted.state,"acknowledged");
 assert.equal(captured.workerID,"worker-a");
 await assert.rejects(()=>recordDeliveryOutcome({delivery,lease,permit,error:Error("timeout"),
  store:{commitOutcome:async()=>false}}),/LEASE_LOST_OR_OUTCOME_CONFLICT/);
});
