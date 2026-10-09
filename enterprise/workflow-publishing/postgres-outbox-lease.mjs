// Isolated PostgreSQL outbox leasing. Requires dedicated halo_outbox_worker role.
// No outbound network transport; never used by live HALO without configuration.
import {randomUUID} from "node:crypto";
const valid=x=>typeof x==="string"&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(x);
export class PostgresOutboxLeaseStore {
 constructor(pool){if(!pool||typeof pool.connect!=="function")throw TypeError("pool required");this.pool=pool;}
 async withRole(callback){
  const c=await this.pool.connect();let started=false;
  try {
   await c.query("BEGIN");started=true;
   await c.query("SET LOCAL ROLE halo_outbox_worker");
   const result=await callback(c);
   await c.query("COMMIT");started=false;return result;
  }catch(e){if(started)await c.query("ROLLBACK").catch(()=>{});throw e;}
  finally{c.release();}
 }
 async claim({workerID,now,leaseMs}){
  if(!valid(workerID)||!Number.isFinite(now)||!Number.isSafeInteger(leaseMs)||leaseMs<1000)throw TypeError("invalid claim");
  const token=randomUUID();
  return this.withRole(async c=>{
   const result=await c.query(`
    WITH candidate AS (
      SELECT event_id FROM halo_execution.transition_outbox
      WHERE published_at IS NULL AND dead_letter_at IS NULL
       AND available_at <= to_timestamp($1 / 1000.0)
       AND (lease_until IS NULL OR lease_until <= to_timestamp($1 / 1000.0))
      ORDER BY available_at,created_at,event_id
      FOR UPDATE SKIP LOCKED LIMIT 1
    )
    UPDATE halo_execution.transition_outbox e
      SET lease_owner=$2,lease_until=to_timestamp(($1+$3)/1000.0),
          lease_token=$4, attempts=e.attempts+1
    FROM candidate WHERE e.event_id=candidate.event_id
    RETURNING e.event_id,e.tenant_id,e.work_item_id,e.revision,e.action,e.attempts,e.lease_token`,
    [now,workerID,leaseMs,token]);
   const row=result.rows[0];if(!row)return null;
   return {eventID:row.event_id.trim(),tenantID:row.tenant_id,workItemID:row.work_item_id,
    revision:Number(row.revision),action:row.action,attempts:row.attempts,leaseToken:row.lease_token};
  });
 }
 async finalize({workerID,eventID,leaseToken,now,sql,args=[]}){
  if(!valid(workerID)||!valid(eventID)||!valid(leaseToken)||!Number.isFinite(now))throw TypeError("invalid lease");
  return this.withRole(async c=>{
   const r=await c.query(sql,[eventID,workerID,leaseToken,now,...args]);
   return r.rowCount===1;
  });
 }
 async complete(x){return this.finalize({...x,sql:`
  UPDATE halo_execution.transition_outbox SET published_at=to_timestamp($4/1000.0),
    lease_owner=NULL,lease_until=NULL,lease_token=NULL
  WHERE event_id=$1 AND lease_owner=$2 AND lease_token=$3
    AND lease_until>to_timestamp($4/1000.0)
    AND published_at IS NULL AND dead_letter_at IS NULL`});}
 async retry(x){return this.finalize({...x,args:[x.availableAt,x.errorCode],sql:`
  UPDATE halo_execution.transition_outbox SET available_at=to_timestamp($5/1000.0),
    last_error_code=$6,lease_owner=NULL,lease_until=NULL,lease_token=NULL
  WHERE event_id=$1 AND lease_owner=$2 AND lease_token=$3
    AND lease_until>to_timestamp($4/1000.0)
    AND published_at IS NULL AND dead_letter_at IS NULL`});}
 async deadLetter(x){return this.finalize({...x,args:[x.errorCode],sql:`
  UPDATE halo_execution.transition_outbox SET dead_letter_at=to_timestamp($4/1000.0),
    last_error_code=$5,lease_owner=NULL,lease_until=NULL,lease_token=NULL
  WHERE event_id=$1 AND lease_owner=$2 AND lease_token=$3
    AND lease_until>to_timestamp($4/1000.0)
    AND published_at IS NULL AND dead_letter_at IS NULL`});}
}
