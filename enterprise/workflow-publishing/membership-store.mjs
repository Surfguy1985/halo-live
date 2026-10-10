// Trusted server-only identity lookup. The login has no direct table grant and
// can assume only the actor-scoped, SELECT-only membership reader role.
const validID = value => typeof value==="string" && value.length>=1 && value.length<=128;
export class PostgresMembershipLoader {
 constructor(pool) {
   if (!pool || typeof pool.connect!=="function") throw new TypeError("Identity database pool required");
   this.pool=pool;
 }
 async load(subject) {
   if (!validID(subject)) return null;
   const client=await this.pool.connect();
   let active=false,discard=false,rows;
   try {
    await client.query("BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY");
    active=true;
    await client.query("SET LOCAL ROLE halo_identity_membership_reader");
    await client.query("SELECT set_config('halo.actor_id',$1,true)",[subject]);
    ({rows}=await client.query(
      `SELECT tenant_id,active,industry_ids,permissions
       FROM halo_workflow.identity_memberships WHERE actor_id=$1`,[subject]));
    await client.query("COMMIT");active=false;
   } catch(error) {
    if(active){try{await client.query("ROLLBACK");}catch{discard=true;}}
    throw error;
   } finally {client.release(discard);}
   const record=rows[0];
   if (!record || record.active!==true ||
       !validID(record.tenant_id) ||
       !Array.isArray(record.industry_ids) || !record.industry_ids.every(validID) ||
       !Array.isArray(record.permissions) || !record.permissions.every(validID)) return null;
   return {active:true,tenantID:record.tenant_id,
     industryIDs:record.industry_ids,permissions:record.permissions};
 }
}
