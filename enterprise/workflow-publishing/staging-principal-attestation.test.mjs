import test from "node:test";
import assert from "node:assert/strict";
import {attestStagingDatabasePrincipals} from "./staging-principal-attestation.mjs";

const admission={databaseName:"halo_staging_ci",requireTLS:false,
 identityUser:"halo_identity_runtime",workflowUser:"halo_workflow_runtime"};
const row=(user,memberships)=>({session_user:user,current_user:user,
 database_name:"halo_staging_ci",tls:false,rolcanlogin:true,rolinherit:false,
 rolsuper:false,rolcreatedb:false,rolcreaterole:false,rolreplication:false,
 rolbypassrls:false,memberships,direct_relation_acl:false});
const pool=value=>({connect:async()=>({query:async()=>({rows:[value]}),release:()=>{}})});

test("attests exact separate identity and workflow principals",async()=>{
 assert.equal(await attestStagingDatabasePrincipals({admission,
  identityPool:pool(row("halo_identity_runtime",["halo_identity_membership_reader"])),
  workflowPool:pool(row("halo_workflow_runtime",["halo_workflow_executor","halo_workflow_receipt_reader"]))
 }),true);
});

test("rejects unsafe attributes, wrong memberships, direct ACLs, TLS and database drift",async()=>{
 const identity=row("halo_identity_runtime",["halo_identity_membership_reader"]);
 const workflow=row("halo_workflow_runtime",["halo_workflow_executor","halo_workflow_receipt_reader"]);
 for(const changed of [
  {...workflow,rolbypassrls:true},
  {...workflow,memberships:[...workflow.memberships,"halo_identity_membership_reader"]},
  {...workflow,direct_relation_acl:true},
  {...workflow,database_name:"halo_production"},
  {...workflow,tls:true}
 ]){
  await assert.rejects(attestStagingDatabasePrincipals({admission,
   identityPool:pool(identity),workflowPool:pool(changed)
  }),/HALO staging principal attestation denied/);
 }
});

test("rejects shared pools and discards a connection after query failure",async()=>{
 const shared=pool(row("halo_identity_runtime",["halo_identity_membership_reader"]));
 await assert.rejects(attestStagingDatabasePrincipals({admission,identityPool:shared,workflowPool:shared}),
  /HALO staging principal attestation denied/);
 let discarded;
 const broken={connect:async()=>({query:async()=>{throw Error("attestation query failed");},
  release:value=>{discarded=value;}})};
 await assert.rejects(attestStagingDatabasePrincipals({admission,identityPool:broken,
  workflowPool:pool(row("halo_workflow_runtime",["halo_workflow_executor","halo_workflow_receipt_reader"]))
 }),{message:"attestation query failed"});
 assert.equal(discarded,true);
});
