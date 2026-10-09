// Database-backed transition adapter. NOT mounted or enabled by default.
// Caller must supply server-verified session and trusted evidence verifier output.
import {TransitionError} from "./transition-service.mjs";
export class PostgresExecutionStore {
 constructor(pool){if(!pool||typeof pool.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async transaction(tenantID,workItemID,callback){
  const client=await this.pool.connect();
  let started=false;
  try {
   await client.query("BEGIN ISOLATION LEVEL SERIALIZABLE");started=true;
   await client.query("SET LOCAL ROLE halo_workflow_executor");
   await client.query("SELECT set_config('halo.tenant_id',$1,true)",[tenantID]);
   const row=await client.query(
    "SELECT tenant_id,work_item_id,industry_id,template_id,template_version,assignee_id,state,revision FROM halo_execution.work_items WHERE tenant_id=$1 AND work_item_id=$2 FOR UPDATE",
    [tenantID,workItemID]);
   const entry=row.rows[0];
   const item=entry?{id:entry.work_item_id,tenantID:entry.tenant_id,industryID:entry.industry_id,
    templateID:entry.template_id,templateVersion:entry.template_version,assigneeID:entry.assignee_id,
    state:entry.state,revision:Number(entry.revision)}:null;
   const tx={
    getIdempotency:async key=>{
     const r=await client.query("SELECT fingerprint,response FROM halo_execution.transition_receipts WHERE tenant_id=$1 AND work_item_id=$2 AND idempotency_key=$3",[tenantID,workItemID,key]);
     return r.rows[0]?{fingerprint:r.rows[0].fingerprint.trim(),response:r.rows[0].response}:null;
    },
    getLockedWorkItem:async()=>item,
    updateState:async ({expectedRevision,revision,state})=>{
     const r=await client.query("UPDATE halo_execution.work_items SET state=$3,revision=$4 WHERE tenant_id=$1 AND work_item_id=$2 AND revision=$5",
      [tenantID,workItemID,state,revision,expectedRevision]);
     if(r.rowCount!==1)throw new TransitionError("REVISION_CONFLICT");
    },
    appendAudit:async event=>client.query(
     "INSERT INTO halo_execution.transition_audit(tenant_id,work_item_id,revision,actor_id,action,from_state,to_state,idempotency_key) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
     [tenantID,workItemID,event.revision,event.actorID,event.action,event.from,event.to,event.idempotencyKey]),
    appendOutbox:async event=>client.query(
     "INSERT INTO halo_execution.transition_outbox(event_id,tenant_id,work_item_id,revision,action) VALUES($1,$2,$3,$4,$5)",
     [event.eventID,tenantID,workItemID,event.revision,event.action]),
    saveIdempotency:async (key,value)=>client.query(
     "INSERT INTO halo_execution.transition_receipts(tenant_id,work_item_id,idempotency_key,fingerprint,response) VALUES($1,$2,$3,$4,$5::jsonb)",
     [tenantID,workItemID,key,value.fingerprint,JSON.stringify(value.response)])
   };
   const result=await callback(tx);
   await client.query("COMMIT");started=false;return result;
  }catch(e){if(started)await client.query("ROLLBACK").catch(()=>{});throw e;}
  finally{client.release();}
 }
}
