// Internal DB adapter for IntegrationManagementService; never bind directly to HTTP.
export class PostgresIntegrationRegistryStore {
 constructor(pool){if(typeof pool?.connect!=="function")throw TypeError("pg pool required");this.pool=pool;}
 async transaction(tenantID,consumerID,callback){
  const c=await this.pool.connect();let active=false;
  try{
   await c.query("BEGIN ISOLATION LEVEL READ COMMITTED");active=true;
   await c.query("SET LOCAL ROLE halo_registry_manager");
   await c.query("SELECT set_config('halo.tenant_id',$1,true)",[tenantID]);
   // Serializes first insert and updates for one tenant+consumer even without
   // an existing row. Advisory collisions only reduce throughput, not safety.
   await c.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",[tenantID+"|"+consumerID]);
   const locked=await c.query("SELECT revision,enabled,event_types,allowed_actions FROM halo_execution.integration_registrations WHERE tenant_id=$1 AND consumer_id=$2 FOR UPDATE",[tenantID,consumerID]);
   const row=locked.rows[0];
   const tx={
    getReceipt:async key=>{
     const r=await c.query("SELECT expected_revision,subscription,response FROM halo_execution.integration_registry_receipts WHERE tenant_id=$1 AND consumer_id=$2 AND request_id=$3",[tenantID,consumerID,key]);
     return r.rows[0]?{expectedRevision:Number(r.rows[0].expected_revision),subscription:r.rows[0].subscription,result:r.rows[0].response}:null;
    },
    getLockedRegistration:async()=>row?{revision:Number(row.revision),enabled:row.enabled,eventTypes:row.event_types,allowedActions:row.allowed_actions}:null,
    upsertRegistration:async value=>{
     const r=await c.query(`INSERT INTO halo_execution.integration_registrations(tenant_id,consumer_id,enabled,event_types,allowed_actions,revision,updated_by)
       VALUES($1,$2,$3,$4::jsonb,$5::jsonb,$6,$7)
       ON CONFLICT(tenant_id,consumer_id) DO UPDATE SET enabled=EXCLUDED.enabled,
         event_types=EXCLUDED.event_types,allowed_actions=EXCLUDED.allowed_actions,
         revision=EXCLUDED.revision,updated_by=EXCLUDED.updated_by,updated_at=now()
       WHERE halo_execution.integration_registrations.revision=$8 RETURNING revision`,
      [tenantID,consumerID,value.enabled,JSON.stringify(value.eventTypes),
       JSON.stringify(value.allowedActions),value.revision,"system-verified",value.revision-1]);
     if(r.rowCount!==1)throw Error("REVISION_CONFLICT");
    },
    appendAudit:async e=>c.query("INSERT INTO halo_execution.integration_registry_audit(tenant_id,consumer_id,revision,actor_id,action,request_id) VALUES($1,$2,$3,$4,$5,$6)",[tenantID,consumerID,e.revision,e.actorID,e.action,e.requestID]),
    saveReceipt:async(key,value)=>c.query("INSERT INTO halo_execution.integration_registry_receipts(tenant_id,consumer_id,request_id,expected_revision,subscription,response) VALUES($1,$2,$3,$4,$5::jsonb,$6::jsonb)",[tenantID,consumerID,key,value.expectedRevision,JSON.stringify(value.subscription),JSON.stringify(value.result)])
   };
   const result=await callback(tx);
   await c.query("COMMIT");active=false;return result;
  }catch(error){if(active)await c.query("ROLLBACK").catch(()=>{});throw error;}
  finally{c.release();}
 }
}
