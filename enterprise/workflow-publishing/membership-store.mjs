// Trusted server-only identity lookup. Uses separate privileged identity pool;
// never give this credential to end users or to the workflow executor.
const validID = value => typeof value==="string" && value.length>=1 && value.length<=128;
export class PostgresMembershipLoader {
 constructor(pool) {
   if (!pool || typeof pool.query!=="function") throw new TypeError("Identity database pool required");
   this.pool=pool;
 }
 async load(subject) {
   if (!validID(subject)) return null;
   const {rows}=await this.pool.query(
     `SELECT tenant_id,active,industry_ids,permissions
      FROM halo_workflow.identity_memberships WHERE actor_id=$1`,[subject]);
   const record=rows[0];
   if (!record || record.active!==true ||
       !validID(record.tenant_id) ||
       !Array.isArray(record.industry_ids) || !record.industry_ids.every(validID) ||
       !Array.isArray(record.permissions) || !record.permissions.every(validID)) return null;
   return {active:true,tenantID:record.tenant_id,
     industryIDs:record.industry_ids,permissions:record.permissions};
 }
}
