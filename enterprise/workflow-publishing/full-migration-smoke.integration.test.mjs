import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
import {fileURLToPath} from "node:url";

const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw Error("Disposable halo_test_* database required");

test("ordered migrations 001–023: complete schema with FORCE RLS", {skip:!url},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:3});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  // Migration 002 explicitly requires a DBA-provisioned executor.
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  const dir=fileURLToPath(new URL("./migrations/",import.meta.url));
  const files=(await readdir(dir)).filter(f=>/^\d{3}_[a-z0-9_]+\.sql$/.test(f)).sort();
  assert.equal(files.length,23,"Update the migration manifest when adding migrations");
  for(let i=0;i<files.length;i++)
   assert.equal(Number(files[i].slice(0,3)),i+1,"Migration number gap");
  for(const name of files){
   await pool.query(await readFile(new URL("./migrations/"+name,import.meta.url),"utf8"));
  }
  const result=await pool.query(
   "SELECT n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('halo_workflow','halo_execution') AND c.relkind='r'");
  assert.ok(result.rowCount>=10,"Missing expected application tables");
  const roles=await pool.query(`SELECT rolname,rolcanlogin,rolbypassrls,rolsuper,rolcreaterole
   FROM pg_roles WHERE rolname=ANY($1::text[])`,[[
    "halo_workflow_executor","halo_outbox_worker","halo_consumer_dispatcher",
    "halo_registry_manager","halo_permit_gateway","halo_delivery_outcome_writer",
    "halo_reconciliation_writer","halo_financial_approval_writer",
    "halo_workflow_receipt_reader"
   ]]);
  assert.equal(roles.rowCount,9,"All restricted worker roles must exist");
  for(const role of roles.rows){
   assert.equal(role.rolcanlogin,false,role.rolname+" must not have LOGIN");
   assert.equal(role.rolbypassrls,false,role.rolname+" must not bypass tenant RLS");
   assert.equal(role.rolsuper,false,role.rolname+" must not be superuser");
   assert.equal(role.rolcreaterole,false,role.rolname+" must not create roles");
  }
  const receiptReader=await pool.query(`SELECT
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.template_heads','SELECT') AS can_read_heads,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.publish_idempotency','SELECT') AS can_read_receipts,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.template_heads','INSERT') AS can_insert_heads,
   has_table_privilege('halo_workflow_receipt_reader','halo_workflow.publish_idempotency','UPDATE') AS can_update_receipts`);
  assert.deepEqual(receiptReader.rows[0],{
   can_read_heads:true,can_read_receipts:true,can_insert_heads:false,can_update_receipts:false
  });
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
