import test from "node:test";
import assert from "node:assert/strict";
import {generateKeyPairSync,sign} from "node:crypto";
import {createEnterpriseWorkflowPipeline} from "./enterprise-pipeline.mjs";
const pair=generateKeyPairSync("rsa",{modulusLength:2048});
const now=1_700_000_000;
const enc=v=>Buffer.from(JSON.stringify(v)).toString("base64url");
const data=enc({alg:"RS256",typ:"JWT",kid:"kid1"})+"."+enc({iss:"https://id.example",aud:"halo-api",sub:"actor-1",iat:now-30,exp:now+600});
const bearer=data+"."+sign("RSA-SHA256",Buffer.from(data),pair.privateKey).toString("base64url");
const layout={schemaVersion:1,tenantID:"tenant-a",templateID:"template",templateVersion:1,
 industryID:"construction",blocks:[]};
const request=(token=bearer)=>({method:"POST",path:"/v1/workflow-templates/template/publish",
 headers:{"authorization":"Bearer "+token,"content-type":"application/json","idempotency-key":"one"},
 body:JSON.stringify({requestID:"one",expectedRevision:0,layout})});
function make({active=true,enabled=true,reconciliationLookup=false}={}) {
 const calls={writes:0,queries:0,workflowSQL:[]};
 const workflowPool={connect:async()=>{
  calls.writes++;
  if(!reconciliationLookup)throw Error("STOP_BEFORE_SQL");
  return {query:async sql=>{
   calls.workflowSQL.push(sql);
   if(sql.includes("SELECT trim(receipt.request_sha256)"))return {rows:[],rowCount:0};
   return {rows:[],rowCount:0};
  },release:()=>{}};
 }};
 const identityPool={connect:async()=>({query:async(sql,args)=>{
  if(sql.includes("FROM halo_workflow.identity_memberships")){
   calls.queries++;assert.deepEqual(args,["actor-1"]);
   return {rows:[{tenant_id:"tenant-a",active,industry_ids:["construction"],permissions:["workflow:publish"]}]};
  }
  if(sql.includes("set_config"))assert.deepEqual(args,["actor-1"]);
  return {rows:[]};
 },release:()=>{}})};
 const gateway=createEnterpriseWorkflowPipeline({issuer:"https://id.example",audience:"halo-api",
  fetchJWKS:async()=>({keys:[{...pair.publicKey.export({format:"jwk"}),kid:"kid1",kty:"RSA",alg:"RS256",use:"sig"}]}),
  identityPool,workflowPool,enabled,clock:()=>now*1000});
 return {gateway,calls};
}
test("valid signed token reaches trusted membership then DB transaction boundary",async()=>{
 const {gateway,calls}=make();
 const result=await gateway(request());
 assert.equal(result.status,500); // SQL intentionally unavailable in this contract test.
 assert.equal(calls.queries,1);
 assert.equal(calls.writes,1);
});
test("revoked membership denies before workflow SQL",async()=>{
 const {gateway,calls}=make({active:false});
 assert.equal((await gateway(request())).status,403);
 assert.equal(calls.writes,0);
});
test("invalid signature denies before membership or SQL",async()=>{
 const {gateway,calls}=make();
 assert.equal((await gateway(request(bearer.slice(0,-3)+"abc"))).status,401);
 assert.equal(calls.queries,0);
 assert.equal(calls.writes,0);
});
test("disabled feature flag denies publishing and never enters SQL",async()=>{
 const {gateway,calls}=make({enabled:false});
 assert.equal((await gateway(request())).status,404);
 assert.equal(calls.writes,0);
});
test("signed reconciliation reaches a receipt-only read transaction through the composed pipeline",async()=>{
 const {gateway,calls}=make({reconciliationLookup:true});
 const original=request();
 original.path="/v1/workflow-templates/template/reconcile";
 const result=await gateway(original);
 assert.equal(result.status,404);
 assert.deepEqual(JSON.parse(result.body),{error:"PUBLISH_REQUEST_NOT_FOUND"});
 assert.equal(calls.queries,1);
 assert.match(calls.workflowSQL[0],/READ ONLY/);
 assert.equal(calls.workflowSQL.some(sql=>/\b(?:INSERT|UPDATE|DELETE)\b/.test(sql)),false);
});
