import test from "node:test";
import assert from "node:assert/strict";
import {attestStagingDatabasePrincipals,STAGING_PRINCIPAL_ATTESTATION_SQL} from "./staging-principal-attestation.mjs";

const admission={databaseName:"halo_staging_ci",requireTLS:false,
 identityUser:"halo_identity_runtime",workflowUser:"halo_workflow_runtime"};
const reachableRole=(role_name,rolcanlogin=false)=>({role_name,rolcanlogin,rolinherit:false,
 rolsuper:false,rolcreatedb:false,rolcreaterole:false,rolreplication:false,
 rolbypassrls:false,owns_database:false,owns_protected_schema:false,
 owns_protected_relation:false});
const row=(user,memberships)=>({session_user:user,current_user:user,
 database_name:"halo_staging_ci",tls:false,rolcanlogin:true,rolinherit:false,
 rolsuper:false,rolcreatedb:false,rolcreaterole:false,rolreplication:false,
 rolbypassrls:false,memberships,reachable_admin_option:false,
 direct_schema_acl:false,direct_relation_acl:false,
 reachable_roles:[reachableRole(user,true),...memberships.map(name=>reachableRole(name))]
  .sort((left,right)=>left.role_name.localeCompare(right.role_name))});
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
  {...workflow,direct_schema_acl:true},
  {...workflow,direct_relation_acl:true},
  {...workflow,database_name:"halo_production"},
  {...workflow,tls:true}
 ]){
  await assert.rejects(attestStagingDatabasePrincipals({admission,
   identityPool:pool(identity),workflowPool:pool(changed)
  }),/HALO staging principal attestation denied/);
 }
});

test("rejects unsafe or owning reachable parent roles and transitive membership drift",async()=>{
 const identity=row("halo_identity_runtime",["halo_identity_membership_reader"]);
 const workflow=row("halo_workflow_runtime",["halo_workflow_executor","halo_workflow_receipt_reader"]);
 const changedRole=(property,value)=>({...workflow,reachable_roles:workflow.reachable_roles.map(role=>
  role.role_name==="halo_workflow_executor"?{...role,[property]:value}:role)});
 for(const changed of [
  changedRole("rolbypassrls",true),
  changedRole("rolsuper",true),
  changedRole("rolcanlogin",true),
  changedRole("rolinherit",true),
  changedRole("rolcreatedb",true),
  changedRole("rolcreaterole",true),
  changedRole("rolreplication",true),
  changedRole("owns_database",true),
  changedRole("owns_protected_schema",true),
  changedRole("owns_protected_relation",true),
  {...workflow,reachable_roles:[...workflow.reachable_roles,reachableRole("halo_transitive_parent")]
   .sort((left,right)=>left.role_name.localeCompare(right.role_name))},
  {...workflow,reachable_admin_option:true},
  {...workflow,reachable_roles:undefined},
  {...workflow,reachable_roles:workflow.reachable_roles.slice(1)},
  {...workflow,reachable_roles:[...workflow.reachable_roles,workflow.reachable_roles[0]]}
 ]){
  await assert.rejects(attestStagingDatabasePrincipals({admission,
   identityPool:pool(identity),workflowPool:pool(changed)
  }),/HALO staging principal attestation denied/);
 }
});

test("attestation SQL recursively inspects role attributes and protected ownership",()=>{
 assert.match(STAGING_PRINCIPAL_ATTESTATION_SQL,/WITH RECURSIVE/);
 assert.match(STAGING_PRINCIPAL_ATTESTATION_SQL,/pg_database/);
 assert.match(STAGING_PRINCIPAL_ATTESTATION_SQL,/nspowner/);
 assert.match(STAGING_PRINCIPAL_ATTESTATION_SQL,/relowner/);
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
