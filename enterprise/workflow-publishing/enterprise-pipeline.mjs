// Isolated composition root. Nothing here binds an HTTP port or touches live HALO.
// Verified identity comes from a trusted configured JWKS provider; active membership
// comes from a separate server-owned database role.
import {RotatingJWTVerifier} from "./rotating-jwks.mjs";
import {PostgresMembershipLoader} from "./membership-store.mjs";
import {createTrustedSessionResolver,createAuthenticatedWorkflowGateway} from "./trusted-auth.mjs";
import {PostgresWorkflowStore} from "./postgres-store.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";
import {createStageTracer} from "./stage-tracer.mjs";

export function createEnterpriseWorkflowPipeline({
 issuer,audience,fetchJWKS,identityPool,workflowPool,enabled=false,clock,emitTrace=()=>{}
}={}) {
 if(typeof enabled!=="boolean") throw TypeError("enabled must be boolean");
 const trace=createStageTracer({emit:emitTrace});
 const verifier=new RotatingJWTVerifier({issuer,audience,fetchJWKS,clock});
 const memberships=new PostgresMembershipLoader(identityPool);
 const resolveSession=createTrustedSessionResolver({
  verifyBearer:token=>trace("auth.verify",null,()=>verifier.verify(token)),
  loadMembership:subject=>trace("membership.load",null,()=>memberships.load(subject))
 });
 const basePublisher=new WorkflowTemplatePublisher(new PostgresWorkflowStore(workflowPool));
 const publisher={publish:input=>trace("workflow.publish",null,()=>basePublisher.publish(input))};
 const publishHandler=createWorkflowPublishHandler({publisher,enabled});
 return createAuthenticatedWorkflowGateway({resolveSession,publishHandler});
}
