-- DBA-only isolated role provisioning. Run after migrations 001–003.
-- Never grant superuser, CREATEDB, CREATEROLE, BYPASSRLS or ownership to runtime.
BEGIN;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_workflow_runtime') THEN
  CREATE ROLE halo_workflow_runtime LOGIN NOINHERIT NOBYPASSRLS;
 END IF;
END $$;
-- A deployment system must configure the credential independently, never in git.
GRANT halo_workflow_executor TO halo_workflow_runtime;
REVOKE ALL ON SCHEMA halo_workflow FROM halo_workflow_runtime;
-- No table privileges directly granted. Runtime uses SET ROLE to executor within
-- server-trusted connection boundaries; identity membership uses a separate role.
COMMIT;
