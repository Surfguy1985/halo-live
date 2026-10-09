# Restricted runtime-role rollout (isolated proposal)

**This is not a live credential setup.** The migration creates a role with no embedded password. Provision secret credentials outside source control and rotate using a secret manager.

- The workflow database connection must authenticate as `halo_workflow_runtime`, a non-owner, non-superuser, non-BYPASSRLS role.
- The publishing transaction must explicitly `SET LOCAL ROLE halo_workflow_executor` before any data access. The executor has tenant-scoped RLS and minimum write permissions.
- The identity lookup connection uses a separate dedicated credential with narrowly reviewed `SELECT` access to identity membership only; **never** use privileged schema-owner credentials for runtime.
- SQL `halo.tenant_id` remains a custom setting, not a cryptographically enforced identity. An arbitrary SQL injection capable of setting that parameter may bypass tenant isolation. Protect through strictly parameterized SQL, constrained server interfaces and a professional security review.
- Do not expose database connections to browsers or mobile apps.
- Rehearse migrations and test with the actual login roles before release. Apply permissions carefully: unrestricted role membership or ability to choose arbitrary tenants would be unacceptable.

Still blocking release: restricted identity-reader policy, production issuer configuration, resource-aware membership, API rate limiting, request deadlines, and active monitoring.
