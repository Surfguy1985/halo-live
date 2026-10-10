// Real PostgreSQL integration tests. Opt-in ONLY; requires disposable DB and privileged migration role.
// Run: HALO_WORKFLOW_TEST_DATABASE_URL=postgres://.../halo_test_workflow node --test postgres.integration.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { PostgresWorkflowStore } from "./postgres-store.mjs";
import { WorkflowTemplatePublisher, PublishError } from "./publisher.mjs";

const url = process.env.HALO_WORKFLOW_TEST_DATABASE_URL;
const enabled = Boolean(url);
const dbName = enabled ? new URL(url).pathname.replace(/^\//, "") : "";
if (enabled && !/^halo_test_[a-z0-9_]+$/i.test(dbName))
  throw new Error("Refusing integration tests unless database is named halo_test_*");

const layout = (tenantID, templateID="template") => ({
  schemaVersion:1, tenantID, templateID, templateVersion:1, industryID:"construction",
  blocks:[{id:"assignment-1",title:"Assign",kind:"assignment",order:0,
    required:true,visibleToRoles:["manager"],config:{}}]
});
const session = tenantID => ({
  authenticated:true,tenantID,actorID:"test-actor",
  permissions:["workflow:publish"],industryIDs:["construction"]
});
const request = (tenantID, key, expectedRevision=0, templateID="template") => ({
  session:session(tenantID),templateID,idempotencyKey:key,
  proposal:{expectedRevision,layout:layout(tenantID,templateID)}
});

test("Postgres: concurrent publish, durability, tenant isolation, rollback and retry", {skip:!enabled}, async t => {
  const { Pool } = await import("pg");
  const pool = new Pool({connectionString:url,max:8});
  const client = await pool.connect();
  try {
    // Dedicated database only; do not point this at any real HALO database.
    await client.query("DROP SCHEMA IF EXISTS halo_workflow CASCADE");
    const migration = await readFile(fileURLToPath(new URL("./migrations/001_workflow_publishing.sql",import.meta.url)),"utf8");
    await client.query(migration);
    const executorRole = await client.query("SELECT 1 FROM pg_roles WHERE rolname=$1",["halo_workflow_executor"]);
    if(executorRole.rowCount===0) await client.query("CREATE ROLE halo_workflow_executor NOLOGIN NOINHERIT NOBYPASSRLS");
    const rlsMigration = await readFile(fileURLToPath(new URL("./migrations/002_tenant_rls.sql",import.meta.url)),"utf8");
    await client.query(rlsMigration);
    const membershipMigration=await readFile(fileURLToPath(new URL("./migrations/003_identity_memberships.sql",import.meta.url)),"utf8");
    await client.query(membershipMigration);
    const runtimeMigration=await readFile(fileURLToPath(new URL("./migrations/004_runtime_role.sql",import.meta.url)),"utf8");
    await client.query(runtimeMigration);
    const receiptReaderMigration=await readFile(fileURLToPath(new URL("./migrations/023_workflow_receipt_reader.sql",import.meta.url)),"utf8");
    await client.query(receiptReaderMigration);
    const identityReaderMigration=await readFile(fileURLToPath(new URL("./migrations/024_identity_membership_reader.sql",import.meta.url)),"utf8");
    await client.query(identityReaderMigration);
    const publisher = new WorkflowTemplatePublisher(new PostgresWorkflowStore(pool));

    await t.test("simultaneous first publishes never both win",async()=>{
      const results=await Promise.allSettled([
        publisher.publish(request("tenant-a","one")),
        publisher.publish(request("tenant-a","two"))
      ]);
      assert.equal(results.filter(x=>x.status==="fulfilled").length,1);
      assert.equal(results.filter(x=>x.status==="rejected").length,1);
      const row=await pool.query("SELECT revision FROM halo_workflow.template_heads WHERE tenant_id=$1 AND template_id=$2",["tenant-a","template"]);
      assert.equal(Number(row.rows[0].revision),1);
      const audits=await pool.query("SELECT count(*)::integer AS count FROM halo_workflow.publish_audit WHERE tenant_id=$1",["tenant-a"]);
      assert.equal(audits.rows[0].count,1);
    });

    await t.test("tenant B can use same template and key without observing A",async()=>{
      const b=await publisher.publish(request("tenant-b","one"));
      assert.equal(b.revision,1);
      const count=await pool.query("SELECT tenant_id,count(*)::integer AS n FROM halo_workflow.template_revisions GROUP BY tenant_id");
      assert.deepEqual(new Map(count.rows.map(r=>[r.tenant_id,r.n])),new Map([["tenant-a",1],["tenant-b",1]]));
    });

    await t.test("same key returns stored response and does not create a second audit",async()=>{
      // One of the competing keys is committed; discover its persisted identity.
      const keys=await pool.query("SELECT idempotency_key FROM halo_workflow.publish_idempotency WHERE tenant_id=$1",["tenant-a"]);
      const key=keys.rows[0].idempotency_key;
      const result=await publisher.publish(request("tenant-a",key));
      assert.equal(result.revision,1);
      const input=request("tenant-a",key);
      const reconciled=await publisher.reconcile({session:input.session,templateID:input.templateID,
        idempotencyKey:input.idempotencyKey,proposal:input.proposal});
      assert.deepEqual(reconciled,{requestID:key,outcome:"COMMITTED",result});
      const audit=await pool.query("SELECT count(*)::integer AS n FROM halo_workflow.publish_audit WHERE tenant_id=$1",["tenant-a"]);
      assert.equal(audit.rows[0].n,1);
    });

    await t.test("stale revision rejected without writing",async()=>{
      await assert.rejects(()=>publisher.publish(request("tenant-a","stale")),e=>
        e instanceof PublishError && e.code==="REVISION_CONFLICT");
      const rows=await pool.query("SELECT count(*)::integer AS n FROM halo_workflow.template_revisions WHERE tenant_id=$1",["tenant-a"]);
      assert.equal(rows.rows[0].n,1);
    });

    await t.test("audit failure rolls back revision, receipt and head",async()=>{
      const rollbackTenant="tenant-rollback";
      await pool.query(`CREATE OR REPLACE FUNCTION halo_workflow.block_test_audit() RETURNS trigger
        LANGUAGE plpgsql AS $$ BEGIN IF NEW.tenant_id='tenant-rollback' THEN
          RAISE EXCEPTION 'forced audit failure'; END IF; RETURN NEW; END $$`);
      await pool.query(`CREATE TRIGGER block_test_audit BEFORE INSERT ON halo_workflow.publish_audit
        FOR EACH ROW EXECUTE FUNCTION halo_workflow.block_test_audit()`);
      await assert.rejects(()=>publisher.publish(request(rollbackTenant,"rollback-1")),/forced audit failure/);
      for (const table of ["template_heads","template_revisions","publish_idempotency","publish_audit"]){
        const r=await pool.query(`SELECT count(*)::integer AS n FROM halo_workflow.${table} WHERE tenant_id=$1`,[rollbackTenant]);
        assert.equal(r.rows[0].n,0,table);
      }
    });
    await t.test("revocation and membership isolation survive database reads",async()=>{
      const {PostgresMembershipLoader}=await import("./membership-store.mjs");
      const loader=new PostgresMembershipLoader(pool); // Integration DBA role only.
      await pool.query(`INSERT INTO halo_workflow.identity_memberships
        (actor_id,tenant_id,active,industry_ids,permissions)
        VALUES($1,$2,true,$3::jsonb,$4::jsonb)`,
        ["member-a","tenant-a",JSON.stringify(["construction"]),JSON.stringify(["workflow:publish"])]);
      assert.equal((await loader.load("member-a")).tenantID,"tenant-a");
      assert.equal(await loader.load("unknown-actor"),null);
      await pool.query("UPDATE halo_workflow.identity_memberships SET active=false,revision=revision+1 WHERE actor_id=$1",["member-a"]);
      assert.equal(await loader.load("member-a"),null);
    });
    await t.test("runtime role has no direct table read privileges",async()=>{
      const isolated=await pool.connect();
      try {
        await isolated.query("SET ROLE halo_workflow_runtime");
        await assert.rejects(()=>isolated.query("SELECT * FROM halo_workflow.template_heads"),/permission denied/);
      } finally {
        await isolated.query("RESET ROLE").catch(()=>{});
        isolated.release();
      }
    });
    await t.test("restricted role: no scope denied, scoped reads isolated, cross-tenant insert denied", async()=>{
      // Dedicated connection: never leak SET ROLE to the admin test connection.
      const scoped = await pool.connect();
      try {
        await scoped.query("SET ROLE halo_workflow_executor");
        const empty = await scoped.query("SELECT count(*)::int AS n FROM halo_workflow.template_heads");
        assert.equal(empty.rows[0].n,0);
        await scoped.query("BEGIN");
        await scoped.query("SELECT set_config('halo.tenant_id', $1, true)",["tenant-a"]);
        const a = await scoped.query("SELECT tenant_id FROM halo_workflow.template_heads ORDER BY tenant_id");
        assert.deepEqual(a.rows.map(r=>r.tenant_id),["tenant-a"]);
        await assert.rejects(()=>scoped.query(
          "INSERT INTO halo_workflow.template_heads(tenant_id,template_id,industry_id) VALUES($1,$2,$3)",
          ["tenant-b","probe","construction"]), /row-level security/);
        await scoped.query("ROLLBACK");
      } finally {
        await scoped.query("RESET ROLE").catch(()=>{});
        scoped.release();
      }
    });
  } finally {
    client.release();
    await pool.end();
  }
});
