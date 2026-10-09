// Isolated financial retry approval write. NEVER starts an external retry.
import {authorizeFinancialRetry} from "./financial-dual-control.mjs";
export class PostgresFinancialApprovalStore {
 constructor(pool){if(typeof pool?.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async propose({delivery,receipt,requester,approver,expectedRevision}={}){
  // An upstream trusted receipt verifier must create receipt; browser assertions
  // about serverVerified are NOT sufficient evidence of non-processing.
  const preliminary=authorizeFinancialRetry({delivery,receipt,requester,approver,expectedRevision});
  const c=await this.pool.connect();let started=false;
  try{
   await c.query("BEGIN");started=true;
   await c.query("SET LOCAL ROLE halo_financial_approval_writer");
   await c.query("SELECT set_config('halo.tenant_id',$1,true)",[preliminary.tenantID]);
   const r=await c.query(`SELECT status,outcome,reconciliation_revision,(available_at='infinity'::timestamptz) AS quarantined,lease_owner FROM
    halo_execution.consumer_deliveries WHERE tenant_id=$1 AND consumer_id=$2
    AND event_id=$3 FOR SHARE`,
    [preliminary.tenantID,preliminary.consumerID,preliminary.eventID]);
   if(r.rowCount!==1 || r.rows[0].status!=="pending" ||
     r.rows[0].outcome!=="uncertain" ||
     r.rows[0].lease_owner!==null ||
     r.rows[0].quarantined!==true ||
     Number(r.rows[0].reconciliation_revision)!==expectedRevision)
    throw Error("RECONCILIATION_STATE_CONFLICT");
   const inserted=await c.query(`INSERT INTO halo_execution.financial_retry_approvals
    (tenant_id,event_id,consumer_id,reconciliation_revision,requested_by,approved_by,verification_id)
    VALUES($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT DO NOTHING RETURNING reconciliation_revision`,
    [preliminary.tenantID,preliminary.eventID,preliminary.consumerID,
     preliminary.nextRevision,preliminary.requestedBy,preliminary.approvedBy,
     preliminary.verificationID]);
   if(inserted.rowCount!==1)throw Error("APPROVAL_ALREADY_EXISTS");
   await c.query("COMMIT");started=false;
   return Object.freeze({...preliminary,stored:true});
  }catch(e){if(started)await c.query("ROLLBACK").catch(()=>{});throw e;}
  finally{c.release();}
 }
}
