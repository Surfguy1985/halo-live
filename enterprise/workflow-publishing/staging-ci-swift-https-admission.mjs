import {isAbsolute} from "node:path";
import {assertCIStagingWorkflowConfiguration} from "./staging-ci-admission.mjs";

const fail=()=>{throw new Error("HALO CI Swift HTTPS signoff admission denied");};
const localPath=value=>typeof value==="string" && isAbsolute(value) && !value.includes("\0");

/**
 * Additional one-purpose admission boundary for the real Swift HTTPS signoff.
 * The base CI admission still fixes the repository, branch, exact SHA,
 * loopback services, synthetic identity, and all disabled side effects.
 */
export function assertCIStagingSwiftHTTPSConfiguration(config=process.env){
 const admission=assertCIStagingWorkflowConfiguration(config);
 if(config.HALO_SWIFT_HTTPS_SIGNOFF_APPROVED!=="ephemeral-ci-https-only" ||
    config.HALO_SWIFT_STAGING_HOST!==admission.publicHost ||
    !localPath(config.HALO_SWIFT_SIGNOFF_EXECUTABLE) ||
    !localPath(config.HALO_SWIFT_TLS_CERTIFICATE) ||
    !localPath(config.HALO_SWIFT_TLS_PRIVATE_KEY)) fail();
 return Object.freeze({...admission,swiftHTTPS:true});
}
