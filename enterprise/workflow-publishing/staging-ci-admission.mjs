// Structurally separate admission policy for the disposable GitHub Actions
// deployment. It cannot admit a real staging or production configuration.
const fail = () => { throw new Error("HALO CI staging admission denied"); };
const parse = value => {
  if(typeof value!=="string" || !value) fail();
  try { return new URL(value); } catch { fail(); }
};
const exactParameters = (url, expected) => {
  const entries=[...url.searchParams.entries()];
  return entries.length===Object.keys(expected).length &&
    entries.every(([key,value])=>expected[key]===value);
};

export function assertCIStagingWorkflowConfiguration(config = process.env) {
  if(config.CI!=="true" || config.GITHUB_ACTIONS!=="true" ||
     config.GITHUB_REPOSITORY!=="Surfguy1985/halo-live" ||
     config.GITHUB_REF!=="refs/heads/codex/halo-enterprise-reconciliation-rc1" ||
     !/^[0-9a-f]{40}$/.test(config.GITHUB_SHA??"") ||
     config.HALO_EXPECTED_RELEASE_SHA!==config.GITHUB_SHA ||
     config.HALO_DEPLOYMENT_ENV!=="ci" ||
     config.HALO_WORKFLOW_PUBLISH_ENABLED!=="true" ||
     config.HALO_WORKFLOW_DEPLOYMENT_APPROVED!=="ephemeral-ci-only" ||
     config.HALO_WORKFLOW_EPHEMERAL_TEST_ONLY!=="true" ||
     config.HALO_WORKFLOW_BIND_HOST!=="127.0.0.1" ||
     config.HALO_WORKFLOW_PORT!=="0" ||
     config.HALO_WORKFLOW_DATABASE_USER!=="halo_workflow_runtime" ||
     config.HALO_IDENTITY_DATABASE_USER!=="halo_identity_runtime") fail();

  for(const name of [
    "HALO_PAYMENTS_ENABLED", "HALO_WEBHOOKS_ENABLED",
    "HALO_DISPATCH_ENABLED", "HALO_ENFORCER_ENABLED"
  ]) if(config[name]!=="false") fail();
  if(config.HALO_OUTBOUND_SIDE_EFFECTS!=="disabled") fail();

  const publicURL=parse(config.HALO_WORKFLOW_PUBLIC_URL);
  if(publicURL.href!=="https://workflow.staging.invalid/" || publicURL.username ||
     publicURL.password || publicURL.search || publicURL.hash) fail();
  const issuer=parse(config.HALO_WORKFLOW_AUTH_ISSUER);
  if(issuer.href!=="https://identity.staging.invalid/ci" ||
     config.HALO_WORKFLOW_AUTH_AUDIENCE!=="halo-staging-ci") fail();

  const database=parse(config.HALO_WORKFLOW_DATABASE_URL);
  if(database.protocol!=="postgresql:" || database.hostname!=="127.0.0.1" ||
     database.port!=="5432" || database.pathname!=="/halo_staging_ci" ||
     database.username!=="postgres" || database.password!=="staging-ci-only" ||
     database.hash || !exactParameters(database,{sslmode:"disable"})) fail();
  const redis=parse(config.HALO_WORKFLOW_REDIS_URL);
  if(redis.href!=="redis://127.0.0.1:6379/0" || redis.username ||
     redis.password || redis.search || redis.hash) fail();

  return Object.freeze({
    environment:"ci",publicHost:"workflow.staging.invalid",
    issuerHost:"identity.staging.invalid",databaseName:"halo_staging_ci",
    bindHost:"127.0.0.1",releaseSHA:config.GITHUB_SHA,
    workflowUser:"halo_workflow_runtime",identityUser:"halo_identity_runtime",
    requireTLS:false
  });
}
