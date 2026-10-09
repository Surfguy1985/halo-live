import test from "node:test";
import assert from "node:assert/strict";
import {decideReconciliation as decide} from "./delivery-reconciliation.mjs";
const session={authenticated:true,tenantID:"tenant-a",actorID:"operator-a",permissions:["deliveries:reconcile"]};
const delivery={tenantID:"tenant-a",consumerID:"accounting",eventID:"a".repeat(64),status:"pending",outcome:"uncertain",reconciliationRevision:0};
const evidence={serverVerified:true,tenantID:"tenant-a",consumerID:"accounting",eventID:delivery.eventID,verificationID:"receipt-a",finding:"processed"};
const args={session,delivery,evidence,resolution:"confirmed_delivered",expectedRevision:0};
test("verified processed receipt allows mark delivered without resending",()=>{
 const result=decide(args);assert.equal(result.nextStatus,"delivered");assert.equal(result.nextOutcome,"acknowledged");
});
test("non-processing confirmation requires matching server verification and explicit retry approval",()=>{
 const verified=decide({...args,resolution:"confirmed_not_processed",evidence:{...evidence,finding:"not_processed"}});
 assert.equal(verified.requiresOperatorRetryApproval,true);
 assert.equal(verified.nextOutcome,"uncertain");
 assert.throws(()=>decide({...args,resolution:"confirmed_not_processed"}),/VERIFICATION_REQUIRED/);
});
test("escalation does not require proof but cannot auto retry",()=>{
 const out=decide({...args,resolution:"escalate",evidence:null});
 assert.equal(out.requiresOperatorRetryApproval,false);assert.equal(out.nextStatus,"pending");
});
test("prevents cross-tenant, stale revision and unsupported status",()=>{
 for(const altered of [{session:{...session,tenantID:"tenant-b"}},{expectedRevision:1},
 {delivery:{...delivery,outcome:"acknowledged"}}])assert.throws(()=>decide({...args,...altered}));
});
