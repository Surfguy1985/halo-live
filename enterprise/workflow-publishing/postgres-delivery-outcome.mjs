// Durable outcome persistence behind verified internal worker identity.
// This adapter is NOT exposed as an HTTP route and requires a restricted pool.
export class PostgresDeliveryOutcomeStore {
 constructor(pool){if(typeof pool?.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async commitOutcome({tenantID,consumerID,eventID,workerID,leaseToken,permitID,registrationRevision,outcome}){
  const c=await this.pool.connect();let active=false;
  try{
   await c.query("BEGIN");active=true;
   await c.query("SET LOCAL ROLE halo_delivery_outcome_writer");
   const r=await c.query(`
    UPDATE halo_execution.consumer_deliveries AS d
    SET outcome=$8,
      outcome_updated_at=now(),
      status=CASE $8 WHEN 'acknowledged' THEN 'delivered' WHEN 'rejected' THEN 'dead_letter' ELSE 'pending' END,
      delivered_at=CASE WHEN $8='acknowledged' THEN now() ELSE d.delivered_at END,
      available_at=CASE WHEN $8='uncertain' THEN 'infinity'::timestamptz ELSE d.available_at END,
      lease_owner=NULL,lease_token=NULL,lease_until=NULL
    WHERE d.tenant_id=$1 AND d.consumer_id=$2 AND d.event_id=$3
      AND d.lease_owner=$4 AND d.lease_token=$5 AND d.lease_until>now()
      AND d.status='pending'
      AND EXISTS (
       SELECT 1 FROM halo_execution.dispatch_permits p
       WHERE p.tenant_id=d.tenant_id AND p.consumer_id=d.consumer_id AND p.event_id=d.event_id
         AND p.permit_id=$6::uuid AND p.registration_revision=$7
         AND p.lease_token=$5 AND p.consumed_at IS NOT NULL
         AND p.consumed_at <= p.expires_at
         AND (p.invalidated_at IS NULL OR p.invalidated_at > p.consumed_at)
      )
    RETURNING d.event_id`,
    [tenantID,consumerID,eventID,workerID,leaseToken,permitID,registrationRevision,outcome.state]);
   if(r.rowCount!==1){await c.query("ROLLBACK");active=false;return false;}
   await c.query(`INSERT INTO halo_execution.delivery_outcome_audit
    (tenant_id,event_id,consumer_id,lease_token,outcome) VALUES ($1,$2,$3,$4,$5)`,
    [tenantID,eventID,consumerID,leaseToken,outcome.state]);
   await c.query("COMMIT");active=false;return true;
  }catch(e){if(active)await c.query("ROLLBACK").catch(()=>{});throw e;}
  finally{c.release();}
 }
}
