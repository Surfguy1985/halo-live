// Isolated per-consumer delivery queue with database lease fencing.
// No live network transport, no webhook endpoints, no credentials.
import {randomUUID} from "node:crypto";
const valid=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class PostgresConsumerDeliveryStore {
 constructor(pool){if(!pool?.connect)throw TypeError("PostgreSQL pool required");this.pool=pool;}
 async transaction(fn){
  const client=await this.pool.connect();let active=false;
  try{await client.query("BEGIN");active=true;await client.query("SET LOCAL ROLE halo_consumer_dispatcher");
   const value=await fn(client);await client.query("COMMIT");active=false;return value;
  }catch(error){if(active)await client.query("ROLLBACK").catch(()=>{});throw error;}
  finally{client.release();}
 }
 async claim({consumerID,workerID,now,leaseMs}){
  if(!valid(consumerID)||!valid(workerID)||!Number.isSafeInteger(leaseMs)||leaseMs<1000||leaseMs>300000)throw TypeError("Invalid claim");
  const token=randomUUID();
  return this.transaction(async c=>{
   const r=await c.query(`
   WITH candidate AS (
    SELECT tenant_id,event_id,consumer_id FROM halo_execution.consumer_deliveries
    WHERE consumer_id=$1 AND status='pending' AND available_at <= clock_timestamp()
      AND (lease_until IS NULL OR lease_until <= clock_timestamp())
    ORDER BY available_at,created_at,tenant_id,event_id FOR UPDATE SKIP LOCKED LIMIT 1
   )
   UPDATE halo_execution.consumer_deliveries d
    SET lease_owner=$3,lease_token=$4,lease_until=clock_timestamp()+($5 * interval '1 millisecond'),attempts=d.attempts+1
   FROM candidate
   WHERE d.tenant_id=candidate.tenant_id AND d.event_id=candidate.event_id AND d.consumer_id=candidate.consumer_id
   RETURNING d.tenant_id,d.event_id,d.consumer_id,d.attempts,d.lease_token`,
   [consumerID,now,workerID,token,leaseMs]);
   if(!r.rows[0])return null;
   const row=r.rows[0];
   return {tenantID:row.tenant_id,eventID:row.event_id.trim(),consumerID:row.consumer_id,
    attempts:row.attempts,leaseToken:row.lease_token};
  });
 }
 async finalize({tenantID,eventID,consumerID,workerID,leaseToken,now,operation,availableAt,errorCode}){
  if(![tenantID,eventID,consumerID,workerID,leaseToken].every(valid)||
     !["complete","retry","dead_letter"].includes(operation))throw TypeError("Invalid lease");
  if(operation==="retry" && (!Number.isFinite(availableAt)||availableAt<Date.now()-1000))throw TypeError("Invalid retry");
  if(operation!=="complete"&&!valid(errorCode))throw TypeError("Invalid error code");
  return this.transaction(async c=>{
   const r=await c.query(`
    UPDATE halo_execution.consumer_deliveries
     SET status=CASE WHEN $6='complete' THEN 'delivered' WHEN $6='dead_letter' THEN 'dead_letter' ELSE status END,
      delivered_at=CASE WHEN $6='complete' THEN clock_timestamp() ELSE delivered_at END,
      available_at=CASE WHEN $6='retry' THEN GREATEST(to_timestamp($8/1000.0),clock_timestamp()) ELSE available_at END,
      last_error_code=CASE WHEN $6='complete' THEN NULL ELSE $9 END,
      lease_owner=NULL,lease_token=NULL,lease_until=NULL
    WHERE tenant_id=$1 AND event_id=$2 AND consumer_id=$3
     AND lease_owner=$4 AND lease_token=$5 AND lease_until>clock_timestamp()
     AND status='pending'
    RETURNING event_id`,
    [tenantID,eventID,consumerID,workerID,leaseToken,operation,now,availableAt??now,errorCode??null]);
   return r.rowCount===1;
  });
 }
 complete(x){return this.finalize({...x,operation:"complete"});}
 retry(x){return this.finalize({...x,operation:"retry"});}
 deadLetter(x){return this.finalize({...x,operation:"dead_letter"});}
}
