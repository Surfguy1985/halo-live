import test from "node:test";
import assert from "node:assert/strict";
import {PostgresMembershipLoader} from "./membership-store.mjs";

const fakePool=(rows,{failLookup=false}={})=>{
 const queries=[];
 let released;
 const client={
  query:async(sql,args)=>{
   queries.push({sql,args});
   if(sql.includes("FROM halo_workflow.identity_memberships")){
    if(failLookup)throw Error("lookup failed");
    return {rows};
   }
   return {rows:[]};
  },
  release:discard=>{released=discard;}
 };
 return {pool:{connect:async()=>client},queries,released:()=>released};
};

test("active membership is loaded in an actor-scoped read-only transaction",async()=>{
 const database=fakePool([
  {active:true,tenant_id:"a",industry_ids:["construction"],permissions:["workflow:publish"]}
 ]);
 const loader=new PostgresMembershipLoader(database.pool);
 const value=await loader.load("actor-1");
 assert.equal(value.tenantID,"a");
 assert.equal(database.queries[0].sql,"BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY");
 assert.equal(database.queries[1].sql,"SET LOCAL ROLE halo_identity_membership_reader");
 assert.deepEqual(database.queries[2].args,["actor-1"]);
 assert.deepEqual(database.queries[3].args,["actor-1"]);
 assert.equal(database.queries.at(-1).sql,"COMMIT");
 assert.equal(database.released(),false);
});
test("revoked, missing and malformed memberships are denied",async()=>{
 for(const rows of [[],[{active:false,tenant_id:"a",industry_ids:[],permissions:[]}],
 [{active:true,tenant_id:"a",industry_ids:"not-array",permissions:[]}]]){
   const database=fakePool(rows);
   const loader=new PostgresMembershipLoader(database.pool);
   assert.equal(await loader.load("actor-1"),null);
   assert.equal(database.queries.at(-1).sql,"COMMIT");
 }
});
test("invalid subject never checks out a database client",async()=>{
 const loader=new PostgresMembershipLoader({connect:async()=>{throw Error("unexpected connection");}});
 assert.equal(await loader.load(""),null);
});

test("lookup failure rolls back and releases the checked-out client",async()=>{
 const database=fakePool([],{failLookup:true});
 const loader=new PostgresMembershipLoader(database.pool);
 await assert.rejects(loader.load("actor-1"),{message:"lookup failed"});
 assert.equal(database.queries.at(-1).sql,"ROLLBACK");
 assert.equal(database.released(),false);
});
