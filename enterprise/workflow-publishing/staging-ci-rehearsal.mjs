// Disposable backup, forward-migration, rollback, restore and reapply proof.
// It accepts only the synthetic GitHub CI staging boundary.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp,readFile,readdir,rm,writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";
import {pathToFileURL} from "node:url";
import {assertCIRecoveryRehearsalConfiguration} from "./staging-ci-rehearsal-admission.mjs";

const POSTGRES_IMAGE="postgres:16@sha256:ca0bd484cb98bf4b24eb1010e73fb3fcbd6714d240fbc1a10eea5b7dbecb641d";
const RESTORE_DATABASE="halo_restore_ci";

async function migrationFiles(last){
 const files=(await readdir(new URL("./migrations/",import.meta.url)))
  .filter(name=>/^\d{3}_[a-z0-9_]+\.sql$/.test(name)).sort();
 assert.equal(files.length,24);
 for(let index=0;index<files.length;index++)assert.equal(Number(files[index].slice(0,3)),index+1);
 return files.slice(0,last);
}

async function applyMigrations(pool,last){
 for(const name of await migrationFiles(last))
  await pool.query(await readFile(new URL("./migrations/"+name,import.meta.url),"utf8"));
}

async function manifest(pool){
 const result=await pool.query(`SELECT
  (SELECT count(*)::integer FROM halo_workflow.identity_memberships) AS memberships,
  (SELECT count(*)::integer FROM halo_workflow.template_heads) AS heads,
  (SELECT count(*)::integer FROM halo_workflow.template_revisions) AS revisions,
  (SELECT count(*)::integer FROM halo_workflow.publish_idempotency) AS idempotency,
  (SELECT count(*)::integer FROM halo_workflow.publish_audit) AS audits,
  (SELECT md5(string_agg(actor_id||':'||tenant_id||':'||active::text,',' ORDER BY actor_id))
   FROM halo_workflow.identity_memberships) AS membership_digest,
  (SELECT md5(string_agg(tenant_id||':'||template_id||':'||revision::text,',' ORDER BY tenant_id,template_id))
   FROM halo_workflow.template_heads) AS head_digest`);
 return result.rows[0];
}

async function seedRepresentativeBaseline(pool){
 await pool.query(`INSERT INTO halo_workflow.identity_memberships
  (actor_id,tenant_id,active,industry_ids,permissions) VALUES
  ('backup-actor-a','staging-tenant',true,'["construction"]','["workflow:publish"]'),
  ('backup-actor-b','staging-tenant',false,'["construction"]','[]')`);
 await pool.query(`INSERT INTO halo_workflow.template_heads
  (tenant_id,template_id,industry_id,revision) VALUES
  ('staging-tenant','construction-dispatch','construction',1)`);
 await pool.query(`INSERT INTO halo_workflow.template_revisions
  (tenant_id,template_id,revision,template_version,layout,layout_sha256,published_by)
  VALUES('staging-tenant','construction-dispatch',1,1,
   '{"schemaVersion":1,"templateID":"construction-dispatch"}',repeat('a',64),'backup-actor-a')`);
 await pool.query(`INSERT INTO halo_workflow.publish_idempotency
  (tenant_id,template_id,idempotency_key,request_sha256,response)
  VALUES('staging-tenant','construction-dispatch','backup-request',repeat('b',64),
   '{"templateID":"construction-dispatch","revision":1,"templateVersion":1}')`);
 await pool.query(`INSERT INTO halo_workflow.publish_audit
  (tenant_id,template_id,revision,actor_id,event_type,content_sha256,idempotency_key)
  VALUES('staging-tenant','construction-dispatch',1,'backup-actor-a',
   'workflow.template.published',repeat('c',64),'backup-request')`);
}

function dockerPostgres(arguments_,input){
 const result=spawnSync("docker",["run","--rm","--network","host",
  "--interactive","-e","PGPASSWORD=staging-ci-only",POSTGRES_IMAGE,...arguments_],{
   env:process.env,input,maxBuffer:50*1024*1024
  });
 if(result.error||result.status!==0)throw new Error("Pinned PostgreSQL recovery command failed");
 return result.stdout;
}

async function assertActorScopedIdentity(pool){
 const client=await pool.connect();
 try{
  await client.query("BEGIN READ ONLY");
  await client.query("SET LOCAL ROLE halo_identity_membership_reader");
  assert.equal((await client.query("SELECT actor_id FROM halo_workflow.identity_memberships")).rowCount,0);
  await client.query("SELECT set_config('halo.actor_id',$1,true)",["backup-actor-a"]);
  assert.deepEqual((await client.query("SELECT actor_id FROM halo_workflow.identity_memberships")).rows,
   [{actor_id:"backup-actor-a"}]);
  await client.query("ROLLBACK");
 }finally{client.release();}
}

async function rollbackIdentityMigration(pool){
 await pool.query(`BEGIN;
  DROP POLICY actor_identity_membership_select ON halo_workflow.identity_memberships;
  REVOKE halo_identity_membership_reader FROM halo_identity_runtime;
  REVOKE SELECT (actor_id,tenant_id,active,industry_ids,permissions)
   ON halo_workflow.identity_memberships FROM halo_identity_membership_reader;
  REVOKE ALL ON SCHEMA halo_workflow FROM halo_identity_membership_reader;
  DROP ROLE halo_identity_runtime;
  DROP ROLE halo_identity_membership_reader;
  COMMIT;`);
 const roles=await pool.query(`SELECT rolname FROM pg_roles
  WHERE rolname IN ('halo_identity_runtime','halo_identity_membership_reader')`);
 assert.equal(roles.rowCount,0);
 const rls=await pool.query(`SELECT relrowsecurity,relforcerowsecurity FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
  WHERE namespace.nspname='halo_workflow' AND relation.relname='identity_memberships'`);
 assert.deepEqual(rls.rows,[{relrowsecurity:true,relforcerowsecurity:true}]);
}

export async function runCIRecoveryRehearsal(config=process.env){
 const admission=assertCIRecoveryRehearsalConfiguration(config);
 const {Pool}=await import("pg");
 const primary=new Pool({connectionString:config.HALO_WORKFLOW_DATABASE_URL,max:3});
 let restored,tempDirectory;
 try{
  await primary.query("DROP SCHEMA IF EXISTS halo_execution CASCADE");
  await primary.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
  await primary.query(`DO $$ BEGIN
   IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_executor') THEN
    CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB
     NOCREATEROLE NOREPLICATION NOBYPASSRLS;
   END IF;
  END $$`);
  await applyMigrations(primary,23);
  await seedRepresentativeBaseline(primary);
  const baseline=await manifest(primary);
  assert.deepEqual({...baseline,membership_digest:undefined,head_digest:undefined},
   {memberships:2,heads:1,revisions:1,idempotency:1,audits:1,
    membership_digest:undefined,head_digest:undefined});
  assert.match(baseline.membership_digest,/^[0-9a-f]{32}$/);
  assert.match(baseline.head_digest,/^[0-9a-f]{32}$/);

  tempDirectory=await mkdtemp(join(tmpdir(),"halo-recovery-rehearsal-"));
  const backupPath=join(tempDirectory,"halo-staging-baseline.dump");
  const backup=dockerPostgres(["pg_dump","--host","127.0.0.1","--port","5432",
   "--username","postgres","--format","custom","--no-owner",
   "--dbname",admission.databaseName]);
  assert.ok(backup.length>1024);
  await writeFile(backupPath,backup,{mode:0o600});
  const savedBackup=await readFile(backupPath);
  const backupSHA256=createHash("sha256").update(savedBackup).digest("hex");

  await primary.query(await readFile(new URL("./migrations/024_identity_membership_reader.sql",import.meta.url),"utf8"));
  await assertActorScopedIdentity(primary);
  await rollbackIdentityMigration(primary);
  assert.deepEqual(await manifest(primary),baseline,"rollback must preserve the pre-024 baseline");

  await primary.query(`DROP DATABASE IF EXISTS ${RESTORE_DATABASE} WITH (FORCE)`);
  await primary.query(`CREATE DATABASE ${RESTORE_DATABASE}`);
  dockerPostgres(["pg_restore","--host","127.0.0.1","--port","5432","--username","postgres",
   "--exit-on-error","--no-owner","--dbname",RESTORE_DATABASE],savedBackup);
  restored=new Pool({host:"127.0.0.1",port:5432,database:RESTORE_DATABASE,
   user:"postgres",password:"staging-ci-only",ssl:false,max:2});
  assert.deepEqual(await manifest(restored),baseline,"restored baseline must match its backup");
  await restored.query(await readFile(new URL("./migrations/024_identity_membership_reader.sql",import.meta.url),"utf8"));
  await assertActorScopedIdentity(restored);
  assert.deepEqual(await manifest(restored),baseline,"reapplying 024 must preserve restored data");

  return Object.freeze({releaseSHA:admission.releaseSHA,tests:"passed",migrations:"001-024",
   backupBytes:backup.length,backupSHA256,rollback:"passed",restore:"passed",reapply:"passed",
   representativeRows:baseline.memberships+baseline.heads+baseline.revisions+
    baseline.idempotency+baseline.audits,outboundSideEffects:0});
 }finally{
  if(restored)await restored.end().catch(()=>{});
  await primary.query(`DROP DATABASE IF EXISTS ${RESTORE_DATABASE} WITH (FORCE)`).catch(()=>{});
  await primary.end().catch(()=>{});
  if(tempDirectory)await rm(tempDirectory,{recursive:true,force:true}).catch(()=>{});
 }
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 runCIRecoveryRehearsal().then(summary=>process.stdout.write(JSON.stringify(summary)+"\n"),error=>{
  process.stderr.write("HALO isolated recovery rehearsal failed: "+error.message+"\n");process.exitCode=1;
 });
}
