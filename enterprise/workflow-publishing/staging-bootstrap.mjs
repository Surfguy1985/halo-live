// Isolated staging-only composition root. No process entrypoint or automatic listen.
// This module never touches the live Base44 mobile transport.
import {assertStagingWorkflowConfiguration} from "./staging-admission.mjs";
import {createEnterpriseWorkflowPipeline} from "./enterprise-pipeline.mjs";
import {createWorkflowReadiness} from "./readiness.mjs";
import {createWorkflowHTTPServer} from "./http-server.mjs";

const deny = () => { throw new Error("HALO staging bootstrap denied"); };

export function createStagingWorkflowBootstrap({
  config, fetchJWKS, identityPool, workflowPool, redis, logger
} = {}) {
  // Admission must precede any use of injected dependencies.
  const admission = assertStagingWorkflowConfiguration(config);
  const port = Number(config.HALO_WORKFLOW_PORT);
  if (!/^(0|[1-9][0-9]{0,4})$/.test(config.HALO_WORKFLOW_PORT ?? "") ||
      !Number.isSafeInteger(port) || port > 65535) deny();
  if(typeof fetchJWKS !== "function" ||
     !identityPool || typeof identityPool.query !== "function" ||
     !workflowPool || typeof workflowPool.query !== "function" ||
     typeof workflowPool.connect !== "function" ||
     identityPool === workflowPool ||
     !redis || typeof redis.ping !== "function" || typeof redis.eval !== "function" ||
     logger !== undefined && typeof logger !== "function") deny();

  const readiness = createWorkflowReadiness({postgres:workflowPool,redis});
  const gateway = createEnterpriseWorkflowPipeline({
    issuer:config.HALO_WORKFLOW_AUTH_ISSUER,
    audience:config.HALO_WORKFLOW_AUTH_AUDIENCE,
    fetchJWKS,identityPool,workflowPool,enabled:true
  });
  const server = createWorkflowHTTPServer({
    gateway,enabled:true,readinessCheck:readiness,
    rateLimitRedis:redis,logger:logger ?? (()=>{})
  });
  let started = false;
  let starting = false;
  return Object.freeze({
    admission,
    async start() {
      if(started || starting) deny();
      starting = true;
      try {
        if(await readiness() !== true) deny();
        await new Promise((resolve,reject)=>{
          const onError=error=>{server.off("listening",onListen);reject(error);};
          const onListen=()=>{server.off("error",onError);resolve();};
          server.once("error",onError);
          server.once("listening",onListen);
          server.listen(port,admission.bindHost);
        });
        started = true;
        return Object.freeze({host:admission.bindHost,port:server.address().port});
      } finally {starting=false;}
    },
    async stop() {
      if(!started) return;
      await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
      started=false;
    },
    metrics() { return server.haloMetrics(); }
  });
}
