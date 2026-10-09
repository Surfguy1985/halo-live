import test from "node:test";
import assert from "node:assert/strict";
import { PostgresWorkflowStore, WorkflowCommitUncertainError } from "./postgres-store.mjs";
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
      if (sql.startsWith("BEGIN") || sql.startsWith("SET LOCAL ROLE") || sql.includes("set_config")) return {rows:[],rowCount:0};
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

test("COMMIT acknowledgement loss is uncertain and destroys pooled connection without retry",async()=>{
 const queries=[],releases=[];
 const pool={connect:async()=>({
  query:async sql=>{
   queries.push(sql);
   if(sql==="COMMIT")throw Object.assign(new Error("connection lost"),{code:"ECONNRESET"});
   return {rows:[],rowCount:0};
  },
  release:discard=>releases.push(discard)
 })};
 const db=new PostgresWorkflowStore(pool);
 await assert.rejects(()=>db.transaction("t1","sample",async()=>({revision:1}),
  "construction","a1"),error=>
   error instanceof WorkflowCommitUncertainError &&
   error.code==="COMMIT_OUTCOME_UNKNOWN" &&
   !error.message.includes("ECONNRESET"));
 assert.equal(queries.filter(x=>x==="COMMIT").length,1);
 assert.equal(queries.filter(x=>x==="ROLLBACK").length,0,
  "ROLLBACK after uncertain COMMIT cannot prove the write was undone");
 assert.deepEqual(releases,[true],"do not return ambiguous session to pool");
});
test("pre-commit callback failure rolls back, propagates original error and returns healthy connection",async()=>{
 const queries=[],releases=[],failure=new Error("audit failure");
 const db=new PostgresWorkflowStore({connect:async()=>({
  query:async sql=>{queries.push(sql);return {rows:[],rowCount:0};},
  release:discard=>releases.push(discard)
 })});
 await assert.rejects(()=>db.transaction("t1","sample",async()=>{throw failure;},
  "construction","a1"),error=>error===failure);
 assert.equal(queries.at(-1),"ROLLBACK");
 assert.deepEqual(releases,[false]);
});
test("failed ROLLBACK destroys connection while preserving original failure",async()=>{
 const queries=[],releases=[],failure=new Error("audit failure");
 const db=new PostgresWorkflowStore({connect:async()=>({
  query:async sql=>{
   queries.push(sql);
   if(sql==="ROLLBACK")throw new Error("rollback transport failed");
   return {rows:[],rowCount:0};
  },
  release:discard=>releases.push(discard)
 })});
 await assert.rejects(()=>db.transaction("t1","sample",async()=>{throw failure;},
  "construction","a1"),error=>error===failure);
 assert.equal(queries.at(-1),"ROLLBACK");
 assert.deepEqual(releases,[true]);
});
test("BEGIN failure does not attempt ROLLBACK and discards connection if connection is broken",async()=>{
 const queries=[],releases=[];
 const db=new PostgresWorkflowStore({connect:async()=>({
  query:async sql=>{
   queries.push(sql);
   if(sql.startsWith("BEGIN"))throw new Error("begin rejected");
   return {rows:[],rowCount:0};
  },
  release:discard=>releases.push(discard)
 })});
 await assert.rejects(()=>db.transaction("t1","sample",async()=>{},
  "construction","a1"),/begin rejected/);
 assert.equal(queries.length,1);
 assert.deepEqual(releases,[false]);
});
