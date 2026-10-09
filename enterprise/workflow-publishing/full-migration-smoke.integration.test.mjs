import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
import {fileURLToPath} from "node:url";

const url=process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
if(url&&!/^halo_test_[a-z0-9_]+$/i.test(new URL(url).pathname.slice(1)))
 throw Error("Disposable halo_test_* database required");

test("ordered migrations 001–022: complete schema with FORCE RLS", {skip:!url},async()=>{
 const {Pool}=await import("pg");
 const pool=new Pool({connectionString:url,max:3});
 try{
  await pool.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await pool.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  // Migration 002 explicitly requires a DBA-provisioned executor.
  await pool.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN CREATE ROLE halo_workflow_executor NOLOGIN NOBYPASSRLS; END IF; END $$");
  const dir=fileURLToPath(new URL("./migrations/",import.meta.url));
  const files=(await readdir(dir)).filter(f=>/^\d{3}_[a-z0-9_]+\.sql$/.test(f)).sort();
  assert.equal(files.length,22,"Update the migration manifest when adding migrations");
  for(let i=0;i<files.length;i++)
   assert.equal(Number(files[i].slice(0,3)),i+1,"Migration number gap");
  for(const name of files){
   await pool.query(await readFile(new URL("./migrations/"+name,import.meta.url),"utf8"));
  }
  const result=await pool.query(
   "SELECT n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('halo_workflow','halo_execution') AND c.relkind='r'");
  assert.ok(result.rowCount>=10,"Missing expected application tables");
  for(const row of result.rows){
   assert.equal(row.relrowsecurity,true,row.nspname+"."+row.relname+" must enable RLS");
   assert.equal(row.relforcerowsecurity,true,row.nspname+"."+row.relname+" must force RLS");
  }
 }finally{await pool.end();}
});
