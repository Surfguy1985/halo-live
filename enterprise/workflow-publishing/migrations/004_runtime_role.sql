-- DBA-only isolated role provisioning. Run after migrations 001–003.
-- Never grant superuser, CREATEDB, CREATEROLE, BYPASSRLS or ownership to runtime.
BEGIN;
DO $$ DECLARE runtime_oid oid; BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_runtime') THEN
  CREATE ROLE halo_workflow_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
   NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 END IF;
 SELECT oid INTO runtime_oid FROM pg_roles
  WHERE rolname='halo_workflow_runtime'
    AND rolcanlogin AND NOT rolinherit AND NOT rolsuper
    AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
    AND NOT rolbypassrls;
 IF runtime_oid IS NULL THEN
  RAISE EXCEPTION 'halo_workflow_runtime has unsafe role attributes';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_auth_members WHERE roleid=runtime_oid) OR
    EXISTS (SELECT 1 FROM pg_auth_members am JOIN pg_roles parent_role ON parent_role.oid=am.roleid
            WHERE am.member=runtime_oid
              AND parent_role.rolname NOT IN ('halo_workflow_executor','halo_workflow_receipt_reader')) THEN
  RAISE EXCEPTION 'halo_workflow_runtime has unexpected role memberships';
 END IF;
END $$;
-- A deployment system must configure the credential independently, never in git.
GRANT halo_workflow_executor TO halo_workflow_runtime;
REVOKE ALL ON SCHEMA halo_workflow FROM halo_workflow_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA halo_workflow FROM halo_workflow_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA halo_workflow FROM halo_workflow_runtime;
-- No table privileges directly granted. Runtime uses SET ROLE to executor within
-- server-trusted connection boundaries; identity membership uses a separate role.
COMMIT;
