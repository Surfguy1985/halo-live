// Trusted transaction adapter, invoked only after server-side operator and evidence verification.
import {decideReconciliation} from "./delivery-reconciliation.mjs";
export class PostgresReconciliationService {
 constructor(pool){if(typeof pool?.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async resolve({session,tenantID,consumerID,eventID,resolution,expectedRevision,evidence}){
  if(!session?.authenticated||session.tenantID!==tenantID||
    !Array.isArray(session.permissions)||!session.permissions.includes("deliveries:reconcile"))
    throw Error("FORBIDDEN");
  const c=await this.pool.connect();let active=false;
  try{
   await c.query("BEGIN");active=true;
   await c.query("SET LOCAL ROLE halo_reconciliation_writer");
   await c.query("SELECT set_config('halo.tenant_id',$1,true)",[tenantID]);
   const r=await c.query(`SELECT tenant_id,consumer_id,event_id,status,outcome,reconciliation_revision
    FROM halo_execution.consumer_deliveries WHERE tenant_id=$1 AND consumer_id=$2 AND event_id=$3 FOR UPDATE`,
    [tenantID,consumerID,eventID]);
   if(r.rowCount!==1)throw Error("NOT_FOUND");
   const row=r.rows[0];
   const decision=decideReconciliation({session,delivery:{
    tenantID:row.tenant_id,consumerID:row.consumer_id,eventID:row.event_id.trim(),
    status:row.status,outcome:row.outcome,reconciliationRevision:Number(row.reconciliation_revision)
   },evidence,resolution,expectedRevision});
   const result=await c.query(`UPDATE halo_execution.consumer_deliveries
    SET reconciliation_revision=$4,
        reconciliation_state=$5,
        status=$6,
        outcome=$7,
        delivered_at=CASE WHEN $5='confirmed_delivered' THEN clock_timestamp() ELSE delivered_at END,
        outcome_updated_at=clock_timestamp()
    WHERE tenant_id=$1 AND consumer_id=$2 AND event_id=$3
      AND reconciliation_revision=$8 AND status='pending' AND outcome='uncertain'
    RETURNING reconciliation_revision`,
    [tenantID,consumerID,eventID,decision.nextRevision,resolution==="escalate"?"escalated":resolution,
     decision.nextStatus,decision.nextOutcome,expectedRevision]);
   if(result.rowCount!==1)throw Error("REVISION_CONFLICT");
   await c.query(`INSERT INTO halo_execution.delivery_reconciliation_audit
    (tenant_id,event_id,consumer_id,revision,operator_id,resolution,verification_id)
    VALUES($1,$2,$3,$4,$5,$6,$7)`,
    [tenantID,eventID,consumerID,decision.nextRevision,session.actorID,resolution,
     evidence?.verificationID??null]);
   await c.query("COMMIT");active=false;
   return decision;
  }catch(e){if(active)await c.query("ROLLBACK").catch(()=>{});throw e;}
  finally{c.release();}
 }
}
