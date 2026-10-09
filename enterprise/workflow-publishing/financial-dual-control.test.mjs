import test from "node:test";
import assert from "node:assert/strict";
import {authorizeFinancialRetry as decide,FinancialControlError} from "./financial-dual-control.mjs";
const delivery={tenantID:"tenant-a",consumerID:"accounting",eventID:"a".repeat(64),outcome:"uncertain",status:"pending",reconciliationRevision:2};
const requester={authenticated:true,tenantID:"tenant-a",actorID:"operator-a",permissions:["financial_retry:request"]};
const approver={authenticated:true,tenantID:"tenant-a",actorID:"director-b",permissions:["financial_retry:approve"]};
const receipt={serverVerified:true,finding:"not_processed",tenantID:"tenant-a",consumerID:"accounting",eventID:delivery.eventID,verificationID:"receipt-3",verifierID:"verifier-c"};
const args={delivery,requester,approver,receipt,expectedRevision:2};
test("independent proof plus distinct authorized actors produces approval proposal only",()=>{
 const value=decide(args);assert.equal(value.automaticallySend,false);
 assert.equal(value.approvedBy,"director-b");assert.equal(value.nextRevision,3);
});
test("self approval and colluding verifier identity denied",()=>{
 assert.throws(()=>decide({...args,approver:{...approver,actorID:"operator-a"}}),e=>e.code==="SEPARATION_OF_DUTIES");
 assert.throws(()=>decide({...args,receipt:{...receipt,verifierID:"director-b"}}),e=>e.code==="INDEPENDENT_VERIFIER_REQUIRED");
});
test("unverified, processed, and cross tenant receipts denied",()=>{
 for(const change of [{serverVerified:false},{finding:"processed"},{tenantID:"tenant-b"}])
  assert.throws(()=>decide({...args,receipt:{...receipt,...change}}),FinancialControlError);
});
test("stale revision and wrong tenant administrators denied",()=>{
 assert.throws(()=>decide({...args,expectedRevision:1}),FinancialControlError);
 assert.throws(()=>decide({...args,requester:{...requester,tenantID:"tenant-b"}}),FinancialControlError);
});
