import test from "node:test";
import assert from "node:assert/strict";
import {PostgresMembershipLoader} from "./membership-store.mjs";
test("active membership loaded using parameterized subject",async()=>{
 let query;
 const loader=new PostgresMembershipLoader({query:async(sql,args)=>{
   query={sql,args};
   return {rows:[{active:true,tenant_id:"a",industry_ids:["construction"],permissions:["workflow:publish"]}]};
 }});
 const value=await loader.load("actor-1");
 assert.equal(value.tenantID,"a");
 assert.deepEqual(query.args,["actor-1"]);
});
test("revoked, missing and malformed memberships are denied",async()=>{
 for(const rows of [[],[{active:false,tenant_id:"a",industry_ids:[],permissions:[]}],
 [{active:true,tenant_id:"a",industry_ids:"not-array",permissions:[]}]]){
   const loader=new PostgresMembershipLoader({query:async()=>({rows})});
   assert.equal(await loader.load("actor-1"),null);
 }
});
test("invalid subject never queries database",async()=>{
 const loader=new PostgresMembershipLoader({query:async()=>{throw Error("unexpected query")}});
 assert.equal(await loader.load(""),null);
});
