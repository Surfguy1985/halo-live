// Explicit staging deployment admission check. Not a server entrypoint.
// Call before constructing a staging publisher; never log raw configuration.
import {isIP} from "node:net";

const fail = () => { throw new Error("HALO workflow staging admission denied"); };
const hostIsPublicName = host => Boolean(host) && host.includes(".") &&
  isIP(host) === 0 && host !== "localhost" && !host.endsWith(".localhost");
const stageLabel = host => host.split(".").some(label => label === "staging" || label === "stage");

function parseURL(value, protocols) {
  if(typeof value !== "string" || !value) fail();
  let url;
  try { url = new URL(value); } catch { fail(); }
  if(!protocols.includes(url.protocol) || !hostIsPublicName(url.hostname) ||
     url.hash || url.username && !protocols.includes("postgresql:")) fail();
  return url;
}

/**
 * Fail-closed preflight for a future *explicit* staging bootstrap.
 * This does not enable publishing, open ports, read secrets or deploy anything.
 * Credentials stay inside the caller's config and are never returned.
 */
export function assertStagingWorkflowConfiguration(config = process.env) {
  if(config.HALO_DEPLOYMENT_ENV !== "staging" ||
     config.HALO_WORKFLOW_PUBLISH_ENABLED !== "true" ||
     config.HALO_WORKFLOW_DEPLOYMENT_APPROVED !== "staging-only" ||
     config.HALO_WORKFLOW_BIND_HOST !== "127.0.0.1" ||
     config.HALO_WORKFLOW_DATABASE_USER !== "halo_workflow_runtime" ||
     config.HALO_IDENTITY_DATABASE_USER !== "halo_identity_runtime") fail();

  const publicURL = parseURL(config.HALO_WORKFLOW_PUBLIC_URL, ["https:"]);
  if(!stageLabel(publicURL.hostname) || publicURL.username || publicURL.password ||
     publicURL.search || publicURL.hash || publicURL.pathname !== "/") fail();

  const issuer = parseURL(config.HALO_WORKFLOW_AUTH_ISSUER, ["https:"]);
  if(issuer.username || issuer.password || issuer.search || issuer.hash) fail();
  if(!/^halo-staging-[a-z0-9_-]{3,80}$/.test(config.HALO_WORKFLOW_AUTH_AUDIENCE ?? "")) fail();

  const database = parseURL(config.HALO_WORKFLOW_DATABASE_URL, ["postgresql:", "postgres:"]);
  const databaseParameters = [...database.searchParams.entries()];
  if(!/^\/halo_staging_[a-z0-9_]{3,64}$/.test(database.pathname) ||
     databaseParameters.length !== 1 ||
     databaseParameters[0][0] !== "sslmode" ||
     databaseParameters[0][1] !== "verify-full" || database.hash) fail();

  // Return only non-sensitive admission metadata, never the database URL or password.
  return Object.freeze({
    environment: "staging",
    publicHost: publicURL.hostname,
    issuerHost: issuer.hostname,
    databaseName: database.pathname.slice(1),
    bindHost: "127.0.0.1",
    workflowUser:"halo_workflow_runtime",
    identityUser:"halo_identity_runtime",
    requireTLS:true
  });
}
