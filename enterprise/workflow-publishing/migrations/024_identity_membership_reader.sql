-- Actor-scoped, SELECT-only identity membership access. The runtime login has
-- no direct table privileges and must SET LOCAL ROLE inside a read-only transaction.
BEGIN;
DO $$ DECLARE reader_oid oid; runtime_oid oid; BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_identity_membership_reader') THEN
  CREATE ROLE halo_identity_membership_reader NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB
   NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 END IF;
 SELECT oid INTO reader_oid FROM pg_roles
  WHERE rolname='halo_identity_membership_reader'
    AND NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper
    AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
    AND NOT rolbypassrls;
 IF reader_oid IS NULL THEN
  RAISE EXCEPTION 'halo_identity_membership_reader has unsafe role attributes';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_auth_members WHERE member=reader_oid) OR
    EXISTS (SELECT 1 FROM pg_auth_members am JOIN pg_roles member_role ON member_role.oid=am.member
            WHERE am.roleid=reader_oid AND member_role.rolname<>'halo_identity_runtime') THEN
  RAISE EXCEPTION 'halo_identity_membership_reader has unexpected role memberships';
 END IF;

 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='halo_identity_runtime') THEN
  CREATE ROLE halo_identity_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB
   NOCREATEROLE NOREPLICATION NOBYPASSRLS;
 END IF;
 SELECT oid INTO runtime_oid FROM pg_roles
  WHERE rolname='halo_identity_runtime'
    AND rolcanlogin AND NOT rolinherit AND NOT rolsuper
    AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication
    AND NOT rolbypassrls;
 IF runtime_oid IS NULL THEN
  RAISE EXCEPTION 'halo_identity_runtime has unsafe role attributes';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_auth_members WHERE roleid=runtime_oid) OR
    EXISTS (SELECT 1 FROM pg_auth_members am JOIN pg_roles parent_role ON parent_role.oid=am.roleid
            WHERE am.member=runtime_oid AND parent_role.rolname<>'halo_identity_membership_reader') THEN
  RAISE EXCEPTION 'halo_identity_runtime has unexpected role memberships';
 END IF;
END $$;

REVOKE ALL ON SCHEMA halo_workflow FROM halo_identity_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA halo_workflow FROM halo_identity_runtime;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA halo_workflow FROM halo_identity_runtime;
GRANT USAGE ON SCHEMA halo_workflow TO halo_identity_membership_reader;
GRANT SELECT (actor_id,tenant_id,active,industry_ids,permissions)
 ON halo_workflow.identity_memberships TO halo_identity_membership_reader;
CREATE POLICY actor_identity_membership_select ON halo_workflow.identity_memberships
 FOR SELECT TO halo_identity_membership_reader USING
 (actor_id = nullif(current_setting('halo.actor_id',true),''));
GRANT halo_identity_membership_reader TO halo_identity_runtime;
COMMIT;
