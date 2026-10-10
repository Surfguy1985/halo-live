const denied=()=>{throw new Error("HALO staging principal attestation denied");};

const principalSQL=`SELECT
 session_user AS session_user,
 current_user AS current_user,
 current_database() AS database_name,
 coalesce((SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()),false) AS tls,
 role.rolcanlogin,role.rolinherit,role.rolsuper,role.rolcreatedb,
 role.rolcreaterole,role.rolreplication,role.rolbypassrls,
 coalesce((SELECT array_agg(parent.rolname ORDER BY parent.rolname)
  FROM pg_auth_members membership JOIN pg_roles parent ON parent.oid=membership.roleid
  WHERE membership.member=role.oid),'{}'::name[]) AS memberships,
 EXISTS (SELECT 1 FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
  CROSS JOIN LATERAL aclexplode(coalesce(relation.relacl,'{}'::aclitem[])) acl
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
  if(result?.rows?.length!==1)denied();
  const row=result.rows[0];
  if(row.session_user!==expectedUser || row.current_user!==expectedUser ||
     row.database_name!==admission.databaseName || row.tls!==admission.requireTLS ||
     row.rolcanlogin!==true || row.rolinherit!==false || row.rolsuper!==false ||
     row.rolcreatedb!==false || row.rolcreaterole!==false || row.rolreplication!==false ||
     row.rolbypassrls!==false || row.direct_relation_acl!==false ||
     !exactArray(row.memberships,expectedMemberships))denied();
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
