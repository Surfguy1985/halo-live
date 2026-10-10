// Isolated staging-only composition root. No process entrypoint or automatic listen.
// This module never touches the live Base44 mobile transport.
import {assertStagingWorkflowConfiguration} from "./staging-admission.mjs";
import {assertCIStagingWorkflowConfiguration} from "./staging-ci-admission.mjs";
import {attestStagingDatabasePrincipals} from "./staging-principal-attestation.mjs";
import {createEnterpriseWorkflowPipeline} from "./enterprise-pipeline.mjs";
import {createWorkflowReadiness} from "./readiness.mjs";
import {createWorkflowHTTPServer} from "./http-server.mjs";

const deny = () => { throw new Error("HALO staging bootstrap denied"); };

function createAdmittedWorkflowBootstrap({
  config, fetchJWKS, identityPool, workflowPool, redis, logger
} = {},assertAdmission) {
  // Admission must precede any use of injected dependencies.
  const admission = assertAdmission(config);
  const port = Number(config.HALO_WORKFLOW_PORT);
  if (!/^(0|[1-9][0-9]{0,4})$/.test(config.HALO_WORKFLOW_PORT ?? "") ||
      !Number.isSafeInteger(port) || port > 65535 ||
      (port === 0 && config.HALO_WORKFLOW_EPHEMERAL_TEST_ONLY !== "true")) deny();
  if(typeof fetchJWKS !== "function" ||
     !identityPool || typeof identityPool.connect !== "function" ||
     !workflowPool || typeof workflowPool.query !== "function" ||
     typeof workflowPool.connect !== "function" ||
     identityPool === workflowPool ||
     !redis || typeof redis.ping !== "function" || typeof redis.eval !== "function" ||
     logger !== undefined && typeof logger !== "function") deny();

  const readiness = createWorkflowReadiness({postgres:workflowPool,redis});
  let state = "idle";
  const gateway = createEnterpriseWorkflowPipeline({
    issuer:config.HALO_WORKFLOW_AUTH_ISSUER,
    audience:config.HALO_WORKFLOW_AUTH_AUDIENCE,
    fetchJWKS,identityPool,workflowPool,enabled:true
  });
  // A service can become unhealthy after startup. Never allow a new
  // publishing mutation when PostgreSQL or Redis readiness is lost.
  const guardedGateway = async request => {
    if(state !== "running" || await readiness() !== true) {
      return {status:503,body:JSON.stringify({error:"STAGING_NOT_READY"})};
    }
    return gateway(request);
  };
  const server = createWorkflowHTTPServer({
    gateway:guardedGateway,enabled:true,
    readinessCheck:async()=>state === "running" && await readiness(),
    rateLimitRedis:redis,logger:logger ?? (()=>{})
  });
  return Object.freeze({
    admission,
    async start() {
      if(state !== "idle") deny();
      state = "starting";
      try {
        if(await readiness() !== true) deny();
        await attestStagingDatabasePrincipals({identityPool,workflowPool,admission});
        await new Promise((resolve,reject)=>{
          const cleanup=()=>{server.off("error",onError);server.off("listening",onListen);};
          const onError=error=>{cleanup();reject(error);};
          const onListen=()=>{cleanup();resolve();};
          server.once("error",onError);
          server.once("listening",onListen);
          try {server.listen(port,admission.bindHost);}
          catch(error){cleanup();reject(error);}
        });
        state = "running";
        return Object.freeze({host:admission.bindHost,port:server.address().port});
      } catch(error) {
        state = "idle";
        throw error;
      }
    },
    async stop() {
      if(state === "idle") return;
      if(state !== "running") deny();
      state = "stopping";
      try {
        await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
        state = "idle";
      } catch(error) {
        state = server.listening ? "running" : "idle";
        throw error;
      }
    },
    metrics() { return server.haloMetrics(); }
  });
}

export function createStagingWorkflowBootstrap(options){
 return createAdmittedWorkflowBootstrap(options,assertStagingWorkflowConfiguration);
}

export function createCIStagingWorkflowBootstrap(options){
 return createAdmittedWorkflowBootstrap(options,assertCIStagingWorkflowConfiguration);
}
