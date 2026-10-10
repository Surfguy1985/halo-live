const denied=reason=>{throw new Error("HALO staging principal attestation denied"+
 (reason?` [${reason}]`:""));};

const principalSQL=`SELECT
 session_user AS session_user,
 current_user AS current_user,
 current_database() AS database_name,
 coalesce((SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()),false) AS tls,
 role.rolcanlogin,role.rolinherit,role.rolsuper,role.rolcreatedb,
 role.rolcreaterole,role.rolreplication,role.rolbypassrls,
 coalesce((SELECT jsonb_agg(parent.rolname::text ORDER BY parent.rolname)
  FROM pg_auth_members membership JOIN pg_roles parent ON parent.oid=membership.roleid
  WHERE membership.member=role.oid),'[]'::jsonb) AS memberships,
 EXISTS (SELECT 1 FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
  CROSS JOIN LATERAL aclexplode(relation.relacl) acl
  WHERE namespace.nspname IN ('halo_workflow','halo_execution')
    AND acl.grantee=role.oid) AS direct_relation_acl
FROM pg_roles role WHERE role.rolname=session_user`;

const exactArray=(actual,expected)=>Array.isArray(actual) && actual.length===expected.length &&
 actual.every((value,index)=>value===expected[index]);

async function inspect(pool,expectedUser,expectedMemberships,admission){
 if(!pool || typeof pool.connect!=="function")denied();
 const client=await pool.connect();
 let discard=false;
 try{
  const result=await client.query(principalSQL);
  if(result?.rows?.length!==1)denied("principal-row-count");
  const row=result.rows[0];
  const checks={
   session_user:row.session_user===expectedUser,current_user:row.current_user===expectedUser,
   database_name:row.database_name===admission.databaseName,tls:row.tls===admission.requireTLS,
   rolcanlogin:row.rolcanlogin===true,rolinherit:row.rolinherit===false,
   rolsuper:row.rolsuper===false,rolcreatedb:row.rolcreatedb===false,
   rolcreaterole:row.rolcreaterole===false,rolreplication:row.rolreplication===false,
   rolbypassrls:row.rolbypassrls===false,direct_relation_acl:row.direct_relation_acl===false,
   memberships:exactArray(row.memberships,expectedMemberships)
  };
  const failure=Object.entries(checks).find(([,passed])=>!passed)?.[0];
  if(failure)denied(failure);
 }catch(error){discard=true;throw error;}finally{client.release(discard);}
}

export async function attestStagingDatabasePrincipals({identityPool,workflowPool,admission}={}){
 if(!admission || identityPool===workflowPool)denied();
 await inspect(identityPool,admission.identityUser,["halo_identity_membership_reader"],admission);
 await inspect(workflowPool,admission.workflowUser,
  ["halo_workflow_executor","halo_workflow_receipt_reader"],admission);
 return true;
}

export {principalSQL as STAGING_PRINCIPAL_ATTESTATION_SQL};
