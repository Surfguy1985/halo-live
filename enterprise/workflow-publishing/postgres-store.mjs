// PostgreSQL adapter for WorkflowTemplatePublisher. NOT mounted on a live API.
// Inject a pg-compatible Pool. Database credentials must be backend-only.
// Runtime role/policies are a deployment prerequisite (migration is fail-closed).
// COMMIT can be durable even if its acknowledgement is lost. Never auto-retry
// an uncertain commit; clients must reconcile with the same idempotency key.
export class WorkflowCommitUncertainError extends Error {
  constructor() {
    super("Workflow commit outcome uncertain; reconcile using the original idempotency key");
    this.name = "WorkflowCommitUncertainError";
    this.code = "COMMIT_OUTCOME_UNKNOWN";
  }
}

export class PostgresWorkflowStore {
  constructor(pool) {
    if (!pool || typeof pool.connect !== "function") throw new TypeError("pg-compatible pool required");
    this.pool = pool;
  }

  // Reconciliation never inserts a template head or modifies an idempotency row.
  // The executor role and tenant scope remain transaction-local under RLS.
  async reconcile(tenantID,templateID,key,industryIDs) {
    if (![tenantID,templateID,key].every(x=>typeof x==="string" && /^[A-Za-z0-9_-]{1,128}$/.test(x)) ||
        !Array.isArray(industryIDs) || !industryIDs.length ||
        !industryIDs.every(x=>typeof x==="string" && x.length>0 && x.length<=128))
      throw new TypeError("Trusted reconciliation scope required");
    const client=await this.pool.connect();
    let active=false,discard=false;
    try {
      await client.query("BEGIN READ ONLY");
      active=true;
      await client.query("SET LOCAL ROLE halo_workflow_executor");
      await client.query("SELECT set_config('halo.tenant_id', $1, true)",[tenantID]);
      const result=await client.query(`SELECT i.response FROM halo_workflow.publish_idempotency i
        JOIN halo_workflow.template_heads h
          ON h.tenant_id=i.tenant_id AND h.template_id=i.template_id
        WHERE i.tenant_id=$1 AND i.template_id=$2 AND i.idempotency_key=$3
          AND h.industry_id=ANY($4::text[])`,[tenantID,templateID,key,industryIDs]);
      await client.query("COMMIT");
      active=false;
      return result.rows[0]?.response ?? null;
    }catch(error){
      if(active){try{await client.query("ROLLBACK");}catch{discard=true;}}
      throw error;
    }finally{client.release(discard);}
  }

  async transaction(tenantID, templateID, callback, industryID, actorID) {
    if (![tenantID, templateID, industryID].every(x => typeof x === "string" && x.trim()))
      throw new TypeError("Trusted tenant/template/industry required");
    const client = await this.pool.connect();
    let active = false;
    let committing = false;
    let discardConnection = false;
    try {
      await client.query("BEGIN ISOLATION LEVEL SERIALIZABLE");
      active = true;
      // Restrict DML to the least-privileged executor even if the caller
      // accidentally supplies a more privileged connection. Deployment must
      // use a dedicated runtime login and deny arbitrary SQL to API users.
      await client.query("SET LOCAL ROLE halo_workflow_executor");
      // Transaction-local tenant scope for restrictive RLS policies.
      // tenantID MUST come from a verified server session.
      await client.query("SELECT set_config('halo.tenant_id', $1, true)", [tenantID]);
      // Durable identity and row lock serialize first publishes, too.
      await client.query(
        `INSERT INTO halo_workflow.template_heads(tenant_id,template_id,industry_id)
         VALUES ($1,$2,$3) ON CONFLICT (tenant_id,template_id) DO NOTHING`,
        [tenantID, templateID, industryID]
      );
      const headResult = await client.query(
        `SELECT industry_id,revision FROM halo_workflow.template_heads
         WHERE tenant_id=$1 AND template_id=$2 FOR UPDATE`,
        [tenantID, templateID]
      );
      const head = headResult.rows[0];
      if (!head || head.industry_id !== industryID) {
        throw new Error("Workflow identity missing or industry mismatch");
      }
      const tx = {
        getIdempotency: async key => {
          const r = await client.query(
            `SELECT request_sha256,response FROM halo_workflow.publish_idempotency
             WHERE tenant_id=$1 AND template_id=$2 AND idempotency_key=$3`,
            [tenantID, templateID, key]
          );
          const row = r.rows[0];
          return row ? {fingerprint: row.request_sha256.trim(), response: row.response} : null;
        },
        getTemplate: async () => ({revision: Number(head.revision), industryID:head.industry_id}),
        saveTemplate: async layout => {
          const nextRevision = layout.revision;
          if (!Number.isSafeInteger(nextRevision) || nextRevision !== Number(head.revision) + 1 ||
              layout.tenantID !== tenantID || layout.templateID !== templateID ||
              layout.industryID !== industryID) throw new Error("Invalid revision or scope");
          // Import from domain module to ensure exactly matching canonical hashing.
          const { layoutHash } = await import("./publisher.mjs");
          const r = await client.query(
            `UPDATE halo_workflow.template_heads SET revision=$3,updated_at=now()
             WHERE tenant_id=$1 AND template_id=$2 AND revision=$4`,
            [tenantID,templateID,nextRevision,head.revision]
          );
          if (r.rowCount !== 1) throw new Error("Revision fence failed");
          await client.query(
            `INSERT INTO halo_workflow.template_revisions
             (tenant_id,template_id,revision,template_version,layout,layout_sha256,published_by)
             VALUES($1,$2,$3,$4,$5::jsonb,$6,$7)`,
            [tenantID,templateID,nextRevision,layout.templateVersion,
             JSON.stringify({...layout,revision:undefined}),layoutHash({...layout,revision:undefined}),
             actorID]
          );
        },
        appendAudit: async event => {
          await client.query(
            `INSERT INTO halo_workflow.publish_audit
             (tenant_id,template_id,revision,actor_id,event_type,content_sha256,idempotency_key)
             VALUES($1,$2,$3,$4,$5,$6,$7)`,
            [tenantID,templateID,event.revision,event.actorID,event.event,
             event.contentHash,event.idempotencyKey]
          );
        },
        saveIdempotency: async (key,value) => {
          await client.query(
            `INSERT INTO halo_workflow.publish_idempotency
             (tenant_id,template_id,idempotency_key,request_sha256,response)
             VALUES($1,$2,$3,$4,$5::jsonb)`,
            [tenantID,templateID,key,value.fingerprint,JSON.stringify(value.response)]
          );
        }
      };
      const result = await callback(tx);
      committing = true;
      await client.query("COMMIT");
      committing = false;
      active = false;
      return result;
    } catch (error) {
      // A transport failure while COMMIT is in flight is ambiguous: the
      // server may have committed. Never retry this transaction automatically.
      if (committing) {
        discardConnection = true;
        throw new WorkflowCommitUncertainError();
      }
      if (active) {
        try { await client.query("ROLLBACK"); }
        catch { discardConnection = true; /* preserve original error */ }
      }
      throw error;
    } finally {
      client.release(discardConnection);
    }
  }
}
