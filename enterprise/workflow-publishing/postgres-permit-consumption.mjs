// Isolated database-backed one-time permit consumption. No network sender.
// Uses authoritative registry lock to serialize against registry updates.
export class PostgresPermitConsumptionStore{
 constructor(pool){if(typeof pool?.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async consumeIfAuthorized({tenantID,consumerID,eventID,permitID,registrationRevision}){
  const client=await this.pool.connect();let active=false;
  try{
   await client.query("BEGIN");active=true;
   await client.query("SET LOCAL ROLE halo_permit_gateway");
   // Lock registration: revocation CAS writes wait for this permit transaction.
   // Once transaction commits, delivery must still be authorized at actual
   // network send boundary; already-transmitted requests cannot be recalled.
   const reg=await client.query(`SELECT revision,enabled FROM halo_execution.integration_registrations
     WHERE tenant_id=$1 AND consumer_id=$2 FOR UPDATE`,[tenantID,consumerID]);
   const record=reg.rows[0];
   if(!record||!record.enabled||Number(record.revision)!==registrationRevision){
    await client.query("ROLLBACK");active=false;return false;
   }
   const permit=await client.query(`UPDATE halo_execution.dispatch_permits
    SET consumed_at=clock_timestamp()
    WHERE tenant_id=$1 AND consumer_id=$2 AND event_id=$3 AND permit_id=$4::uuid
      AND registration_revision=$5 AND consumed_at IS NULL AND invalidated_at IS NULL
      AND expires_at>clock_timestamp() RETURNING permit_id`,
    [tenantID,consumerID,eventID,permitID,registrationRevision]);
   const accepted=permit.rowCount===1;
   await client.query("COMMIT");active=false;return accepted;
  }catch(error){if(active)await client.query("ROLLBACK").catch(()=>{});throw error;}
  finally{client.release();}
 }
}
