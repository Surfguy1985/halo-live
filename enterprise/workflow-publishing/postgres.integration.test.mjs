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
  } finally {
    client.release();
    await pool.end();
  }
});
