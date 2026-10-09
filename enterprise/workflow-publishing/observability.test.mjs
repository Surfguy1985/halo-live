import test from "node:test";
import assert from "node:assert/strict";
import {createObservability} from "./observability.mjs";
test("logs safe correlation and counts requests",async()=>{
 const logs=[],o=createObservability({logger:v=>logs.push(v),clock:()=>100});
 const response=await o.wrap(async()=>({status:200,body:"{}"}))({
  method:"POST",headers:{authorization:"Bearer secret"},body:"sensitive"});
 assert.match(response.headers["x-correlation-id"],/^[0-9a-f-]{36}$/);
 assert.equal(o.snapshot().requests,1);
 assert.equal(logs[0].status,200);
 assert.ok(!JSON.stringify(logs).includes("secret"));
 assert.ok(!JSON.stringify(logs).includes("sensitive"));
});
test("converts unexpected failures to redacted errors and records them",async()=>{
 const o=createObservability();
 const r=await o.wrap(async()=>{throw Error("private database error")})({method:"POST"});
 assert.equal(r.status,500);
 assert.equal(o.snapshot().errors,1);
 assert.ok(!r.body.includes("private"));
});
