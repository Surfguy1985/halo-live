const denied=reason=>{throw new Error("HALO staging principal attestation denied"+
 (reason?` [${reason}]`:""));};

const principalSQL=`WITH RECURSIVE login_role AS (
 SELECT role.* FROM pg_roles role WHERE role.rolname=session_user
), reachable_role_ids(oid) AS (
 SELECT oid FROM login_role
 UNION
 SELECT membership.roleid FROM reachable_role_ids reachable
 JOIN pg_auth_members membership ON membership.member=reachable.oid
), inspected_roles AS (
 SELECT role.* FROM reachable_role_ids reachable
 JOIN pg_roles role ON role.oid=reachable.oid
)
SELECT
 session_user AS session_user,
 current_user AS current_user,
 current_database() AS database_name,
 coalesce((SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid()),false) AS tls,
 role.rolcanlogin,role.rolinherit,role.rolsuper,role.rolcreatedb,
 role.rolcreaterole,role.rolreplication,role.rolbypassrls,
 coalesce((SELECT jsonb_agg(parent.rolname::text ORDER BY parent.rolname)
 FROM pg_auth_members membership JOIN pg_roles parent ON parent.oid=membership.roleid
  WHERE membership.member=role.oid),'[]'::jsonb) AS memberships,
 EXISTS (SELECT 1 FROM pg_auth_members membership
  JOIN reachable_role_ids reachable ON reachable.oid=membership.member
  WHERE membership.admin_option) AS reachable_admin_option,
 coalesce((SELECT jsonb_agg(jsonb_build_object(
   'role_name',inspected.rolname,
   'rolcanlogin',inspected.rolcanlogin,
   'rolinherit',inspected.rolinherit,
   'rolsuper',inspected.rolsuper,
   'rolcreatedb',inspected.rolcreatedb,
   'rolcreaterole',inspected.rolcreaterole,
   'rolreplication',inspected.rolreplication,
   'rolbypassrls',inspected.rolbypassrls,
   'owns_database',EXISTS (SELECT 1 FROM pg_database database
    WHERE database.datname=current_database() AND database.datdba=inspected.oid),
   'owns_protected_schema',EXISTS (SELECT 1 FROM pg_namespace namespace
    WHERE namespace.nspname IN ('halo_workflow','halo_execution')
      AND namespace.nspowner=inspected.oid),
   'owns_protected_relation',EXISTS (SELECT 1 FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname IN ('halo_workflow','halo_execution')
      AND relation.relowner=inspected.oid)
  ) ORDER BY inspected.rolname) FROM inspected_roles inspected),'[]'::jsonb)
  AS reachable_roles,
 EXISTS (SELECT 1 FROM pg_namespace namespace
  CROSS JOIN LATERAL aclexplode(namespace.nspacl) acl
  WHERE namespace.nspname IN ('halo_workflow','halo_execution')
    AND acl.grantee=role.oid) AS direct_schema_acl,
 EXISTS (SELECT 1 FROM pg_class relation
  JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
  CROSS JOIN LATERAL aclexplode(relation.relacl) acl
  WHERE namespace.nspname IN ('halo_workflow','halo_execution')
    AND acl.grantee=role.oid) AS direct_relation_acl
FROM login_role role`;

const exactArray=(actual,expected)=>Array.isArray(actual) && actual.length===expected.length &&
 actual.every((value,index)=>value===expected[index]);

const safeReachableRoles=(actual,expectedUser,expectedMemberships)=>{
 if(!Array.isArray(actual))return false;
 const expectedNames=[expectedUser,...expectedMemberships].sort();
 const actualNames=actual.map(role=>role?.role_name);
 if(!exactArray(actualNames,expectedNames))return false;
 return actual.every(role=>role &&
  role.rolcanlogin===(role.role_name===expectedUser) && role.rolinherit===false &&
  role.rolsuper===false && role.rolcreatedb===false && role.rolcreaterole===false &&
  role.rolreplication===false && role.rolbypassrls===false &&
  role.owns_database===false && role.owns_protected_schema===false &&
  role.owns_protected_relation===false);
};

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
   rolbypassrls:row.rolbypassrls===false,direct_schema_acl:row.direct_schema_acl===false,
   direct_relation_acl:row.direct_relation_acl===false,
   memberships:exactArray(row.memberships,expectedMemberships),
   reachable_roles:safeReachableRoles(row.reachable_roles,expectedUser,expectedMemberships),
   reachable_admin_option:row.reachable_admin_option===false
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
