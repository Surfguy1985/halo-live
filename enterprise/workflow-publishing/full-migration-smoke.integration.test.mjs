import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
import {fileURLToPath} from "node:url";

const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw Error("Disposable halo_test_* database required");

test("ordered migrations 001–024: complete schema with FORCE RLS", {skip:!url},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:3});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  // Migration 002 explicitly requires a DBA-provisioned executor.
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOBYPASSRLS; END IF; END $$");
  const dir=fileURLToPath(new URL("./migrations/",import.meta.url));
  const files=(await readdir(dir)).filter(f=>/^\d{3}_[a-z0-9_]+\.sql$/.test(f)).sort();
  assert.equal(files.length,24,"Update the migration manifest when adding migrations");
  for(let i=0;i<files.length;i++)
   assert.equal(Number(files[i].slice(0,3)),i+1,"Migration number gap");
  for(const name of files){
   await pool.query(await readFile(new URL("./migrations/"+name,import.meta.url),"utf8"));
  }
  const result=await pool.query(
   "SELECT n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('halo_workflow','halo_execution') AND c.relkind='r'");
  assert.ok(result.rowCount>=10,"Missing expected application tables");
  const roles=await pool.query(`SELECT rolname,rolcanlogin,rolinherit,rolbypassrls,rolsuper,rolcreaterole
   FROM pg_roles WHERE rolname=ANY($1::text[])`,[[
    "halo_workflow_executor","halo_outbox_worker","halo_consumer_dispatcher",
    "halo_registry_manager","halo_permit_gateway","halo_delivery_outcome_writer",
    "halo_reconciliation_writer","halo_financial_approval_writer",
    "halo_workflow_receipt_reader","halo_identity_membership_reader"
   ]]);
  assert.equal(roles.rowCount,10,"All restricted worker roles must exist");
  for(const role of roles.rows){
   assert.equal(role.rolcanlogin,false,role.rolname+" must not have LOGIN");
   assert.equal(role.rolbypassrls,false,role.rolname+" must not bypass tenant RLS");
   assert.equal(role.rolsuper,false,role.rolname+" must not be superuser");
   assert.equal(role.rolcreaterole,false,role.rolname+" must not create roles");
  }
  for(const name of ["halo_workflow_executor","halo_workflow_receipt_reader","halo_identity_membership_reader"])
   assert.equal(roles.rows.find(role=>role.rolname===name)?.rolinherit,false,
    name+" must require explicit SET ROLE");
  const receiptReader=await pool.query(`SELECT
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.template_heads','SELECT') AS can_read_heads,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.publish_idempotency','SELECT') AS can_read_receipts,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.template_heads','INSERT') AS can_insert_heads,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.publish_idempotency','UPDATE') AS can_update_receipts`);
  assert.deepEqual(receiptReader.rows[0],{
   can_read_heads:true,can_read_receipts:true,can_insert_heads:false,can_update_receipts:false
  });
  const runtimes=await pool.query(`SELECT rolname,rolcanlogin,rolinherit,rolbypassrls,
   rolsuper,rolcreatedb,rolcreaterole,rolreplication FROM pg_roles
   WHERE rolname=ANY($1::text[]) ORDER BY rolname`,[["halo_identity_runtime","halo_workflow_runtime"]]);
  assert.equal(runtimes.rowCount,2);
  for(const role of runtimes.rows){
   assert.equal(role.rolcanlogin,true,role.rolname+" must be a login");
   for(const key of ["rolinherit","rolbypassrls","rolsuper","rolcreatedb","rolcreaterole","rolreplication"])
    assert.equal(role[key],false,role.rolname+" has unsafe "+key);
  }
  const memberships=await pool.query(`SELECT member_role.rolname AS member,parent_role.rolname AS parent
   FROM pg_auth_members am JOIN pg_roles member_role ON member_role.oid=am.member
   JOIN pg_roles parent_role ON parent_role.oid=am.roleid
   WHERE member_role.rolname IN ('halo_identity_runtime','halo_workflow_runtime')
   ORDER BY member,parent`);
  assert.deepEqual(memberships.rows,[
   {member:"halo_identity_runtime",parent:"halo_identity_membership_reader"},
   {member:"halo_workflow_runtime",parent:"halo_workflow_executor"},
   {member:"halo_workflow_runtime",parent:"halo_workflow_receipt_reader"}
  ]);
  const expectUnsafeRoleRejected=async(role,unsafe,restore,migration,pattern)=>{
   await pool.query(`ALTER ROLE ${role} ${unsafe}`);
   try{
    const sql=await readFile(new URL("./migrations/"+migration,import.meta.url),"utf8");
    await assert.rejects(pool.query(sql),pattern);
   }finally{
    await pool.query("ROLLBACK").catch(()=>{});
    await pool.query(`ALTER ROLE ${role} ${restore}`);
   }
  };
  await expectUnsafeRoleRejected("halo_workflow_executor","INHERIT","NOINHERIT",
   "002_tenant_rls.sql",/exact restricted attributes/);
  await expectUnsafeRoleRejected("halo_workflow_runtime","BYPASSRLS","NOBYPASSRLS",
   "004_runtime_role.sql",/unsafe role attributes/);
  await expectUnsafeRoleRejected("halo_workflow_receipt_reader","LOGIN","NOLOGIN",
   "023_workflow_receipt_reader.sql",/unsafe role attributes/);
  await expectUnsafeRoleRejected("halo_identity_membership_reader","LOGIN","NOLOGIN",
   "024_identity_membership_reader.sql",/unsafe role attributes/);
  await pool.query("CREATE ROLE halo_migration_unexpected_parent NOLOGIN");
  await pool.query("GRANT halo_migration_unexpected_parent TO halo_identity_runtime");
  try{
   const identityMigration=await readFile(
    new URL("./migrations/024_identity_membership_reader.sql",import.meta.url),"utf8");
   await assert.rejects(pool.query(identityMigration),/unexpected role memberships/);
  }finally{
   await pool.query("ROLLBACK").catch(()=>{});
   await pool.query("REVOKE halo_migration_unexpected_parent FROM halo_identity_runtime");
   await pool.query("DROP ROLE halo_migration_unexpected_parent");
  }
  const identityPrivileges=await pool.query(`SELECT
   has_column_privilege('halo_identity_membership_reader','halo_workflow.identity_memberships','actor_id','SELECT') AS actor_select,
   has_column_privilege('halo_identity_membership_reader','halo_workflow.identity_memberships','updated_at','SELECT') AS updated_select,
   has_table_privilege('halo_identity_membership_reader','halo_workflow.identity_memberships','INSERT') AS can_insert,
   EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,'{}'::aclitem[])) acl
    JOIN pg_roles grantee ON grantee.oid=acl.grantee
    WHERE n.nspname='halo_workflow' AND c.relname='identity_memberships'
      AND grantee.rolname='halo_identity_runtime') AS runtime_direct_acl`);
  assert.deepEqual(identityPrivileges.rows[0],{
   actor_select:true,updated_select:false,can_insert:false,runtime_direct_acl:false
  });
  await pool.query(`INSERT INTO halo_workflow.identity_memberships
   (actor_id,tenant_id,active,industry_ids,permissions) VALUES
   ('migration-actor-a','tenant-a',true,'[]','[]'),
   ('migration-actor-b','tenant-b',true,'[]','[]')`);
  const identityReader=await pool.connect();
  try{
   await identityReader.query("BEGIN READ ONLY");
   await identityReader.query("SET LOCAL ROLE halo_identity_membership_reader");
   const unscoped=await identityReader.query("SELECT actor_id FROM halo_workflow.identity_memberships");
   assert.equal(unscoped.rowCount,0,"missing actor scope must reveal no memberships");
   await identityReader.query("SELECT set_config('halo.actor_id',$1,true)",["migration-actor-a"]);
   const scoped=await identityReader.query("SELECT actor_id FROM halo_workflow.identity_memberships");
   assert.deepEqual(scoped.rows,[{actor_id:"migration-actor-a"}]);
   await assert.rejects(()=>identityReader.query(
    "UPDATE halo_workflow.identity_memberships SET active=false WHERE actor_id='migration-actor-a'"),
    /permission denied|read-only transaction/);
   await identityReader.query("ROLLBACK");
  }finally{identityReader.release();}
  // Financial approvals must be inaccessible without a trusted tenant context.
  const worker=await pool.connect();
  try{
   await worker.query("BEGIN");
   await worker.query("SET LOCAL ROLE halo_financial_approval_writer");
   const invisible=await worker.query(
    "SELECT count(*)::integer AS n FROM halo_execution.financial_retry_approvals");
   assert.equal(invisible.rows[0].n,0);
   await worker.query("ROLLBACK");
  }finally{worker.release();}
  for(const row of result.rows){
   assert.equal(row.relrowsecurity,true,row.nspname+"."+row.relname+" must enable RLS");
   assert.equal(row.relforcerowsecurity,true,row.nspname+"."+row.relname+" must force RLS");
  }
 }finally{await pool.end();}
});
