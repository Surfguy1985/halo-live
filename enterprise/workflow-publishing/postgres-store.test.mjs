import test from "node:test";
import assert from "node:assert/strict";
import { PostgresWorkflowStore } from "./postgres-store.mjs";
import { WorkflowTemplatePublisher } from "./publisher.mjs";

// SQL-protocol fake: validates query ordering and transaction boundaries.
// NOT a replacement for PostgreSQL concurrency or RLS integration tests.
function fakePool({ failAudit = false } = {}) {
  const calls = [];
  let released = 0;
  const state = { head: null, revision: null, receipt: null, audit: null };
  const client = {
    async query(sql, args = []) {
      calls.push(sql.trim().split(/\s+/).slice(0, 5).join(" ").toUpperCase());
      if (sql.startsWith("BEGIN") || sql.includes("set_config")) return {rows:[],rowCount:0};
      if (sql === "COMMIT" || sql === "ROLLBACK") return {rows:[],rowCount:0};
      if (sql.includes("INSERT INTO halo_workflow.template_heads")) {
        if (!state.head) state.head={industry_id:args[2],revision:0};
        return {rows:[],rowCount:1};
      }
      if (sql.includes("SELECT industry_id,revision")) return {rows:[state.head],rowCount:1};
      if (sql.includes("SELECT request_sha256,response")) return {rows:state.receipt?[state.receipt]:[],rowCount:state.receipt?1:0};
      if (sql.includes("UPDATE halo_workflow.template_heads")) {
        if (state.head.revision !== Number(args[3])) return {rows:[],rowCount:0};
        state.head.revision=args[2];return {rows:[],rowCount:1};
      }
      if (sql.includes("INSERT INTO halo_workflow.template_revisions")) {
        state.revision=args;return {rows:[],rowCount:1};
      }
      if (sql.includes("INSERT INTO halo_workflow.publish_idempotency")) {
        state.receipt={request_sha256:args[3],response:JSON.parse(args[4])};
        return {rows:[],rowCount:1};
      }
      if (sql.includes("INSERT INTO halo_workflow.publish_audit")) {
        if (failAudit) throw new Error("audit unavailable");
        state.audit=args;return {rows:[],rowCount:1};
      }
      throw new Error("Unexpected SQL: "+sql);
    },
    release() {released++;}
  };
  return {pool:{connect:async()=>client},calls,state,get released(){return released;}};
}
const layout={schemaVersion:1,templateID:"sample",templateVersion:1,tenantID:"t1",
  industryID:"construction",blocks:[{id:"a",kind:"assignment",title:"Assign",order:0,
  required:true,visibleToRoles:["manager"],config:{}}]};
const session={authenticated:true,tenantID:"t1",actorID:"a1",
  industryIDs:["construction"],permissions:["workflow:publish"]};
test("PostgreSQL adapter publishes under transaction and commits audit after receipt",async()=>{
  const db=fakePool();
  const svc=new WorkflowTemplatePublisher(new PostgresWorkflowStore(db.pool));
  const result=await svc.publish({session,templateID:"sample",idempotencyKey:"key1",
    proposal:{expectedRevision:0,layout}});
  assert.equal(result.revision,1);
  assert.equal(db.state.revision[2],1);
  assert.ok(db.state.audit);
  assert.equal(db.calls.at(-1),"COMMIT");
  assert.equal(db.released,1);
  const receiptIndex=db.calls.findIndex(x=>x.includes("PUBLISH_IDEMPOTENCY"));
  const auditIndex=db.calls.findIndex(x=>x.includes("PUBLISH_AUDIT"));
  assert.ok(receiptIndex >= 0 && auditIndex > receiptIndex);
});
test("PostgreSQL adapter requests rollback and releases connection on audit failure",async()=>{
  const db=fakePool({failAudit:true});
  const svc=new WorkflowTemplatePublisher(new PostgresWorkflowStore(db.pool));
  await assert.rejects(()=>svc.publish({session,templateID:"sample",idempotencyKey:"key1",
    proposal:{expectedRevision:0,layout}}),/audit unavailable/);
  assert.equal(db.calls.at(-1),"ROLLBACK");
  assert.equal(db.released,1);
});
test("PostgreSQL adapter rejects missing trusted scope before acquiring connection",async()=>{
  const db=fakePool();
  const store=new PostgresWorkflowStore(db.pool);
  await assert.rejects(()=>store.transaction("t1","sample",async()=>{},undefined,"a1"),TypeError);
  assert.equal(db.released,0);
});
