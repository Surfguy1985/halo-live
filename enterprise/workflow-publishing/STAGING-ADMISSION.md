# Staging-only publishing admission

`staging-admission.mjs` provides a fail-closed, side-effect-free preflight for a
**future** explicitly reviewed staging bootstrap. It is not wired into the live
Base44 app, native `HaloAPI`, or a deployed Node process.

Before enabling any staging publisher, a deployment integration must call
`assertStagingWorkflowConfiguration(config)` and use its approved loopback bind
address. Required configuration:

- `HALO_DEPLOYMENT_ENV=staging`
- `HALO_WORKFLOW_PUBLISH_ENABLED=true`
- `HALO_WORKFLOW_DEPLOYMENT_APPROVED=staging-only`
- `HALO_WORKFLOW_BIND_HOST=127.0.0.1`
- `HALO_WORKFLOW_PUBLIC_URL`: HTTPS URL with an exact `staging` or `stage` DNS label
- `HALO_WORKFLOW_AUTH_ISSUER`: HTTPS issuer
- `HALO_WORKFLOW_AUTH_AUDIENCE`: `halo-staging-...`
- `HALO_WORKFLOW_DATABASE_URL`: PostgreSQL database named `halo_staging_...`
  with `sslmode=verify-full`, on a non-loopback DNS host

The guard does **not** prove actual DNS ownership, certificate trust, identity
provider configuration, PostgreSQL isolation, secrets management, or deployment
safety. These must be independently verified, along with network policy,
migration backups, signed token rotation, rate limiting, audit retention, and
a human-approved release. The guard intentionally does not start a server or
turn on the feature flag.

Tests: `node --test enterprise/workflow-publishing/staging-admission.test.mjs`.
