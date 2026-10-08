// Isolated composition root. Nothing here binds an HTTP port or touches live HALO.
// Verified identity comes from a trusted configured JWKS provider; active membership
// comes from a separate server-owned database role.
import {RotatingJWTVerifier} from "./rotating-jwks.mjs";
import {PostgresMembershipLoader} from "./membership-store.mjs";
import {createTrustedSessionResolver,createAuthenticatedWorkflowGateway} from "./trusted-auth.mjs";
import {PostgresWorkflowStore} from "./postgres-store.mjs";
import {WorkflowTemplatePublisher} from "./publisher.mjs";
import {createWorkflowPublishHandler} from "./api-handler.mjs";

export function createEnterpriseWorkflowPipeline({
 issuer,audience,fetchJWKS,identityPool,workflowPool,enabled=false,clock
}={}) {
 if(typeof enabled!=="boolean") throw TypeError("enabled must be boolean");
 const verifier=new RotatingJWTVerifier({issuer,audience,fetchJWKS,clock});
 const memberships=new PostgresMembershipLoader(identityPool);
 const resolveSession=createTrustedSessionResolver({
  verifyBearer:token=>verifier.verify(token),
  loadMembership:subject=>memberships.load(subject)
 });
 const publisher=new WorkflowTemplatePublisher(new PostgresWorkflowStore(workflowPool));
 const publishHandler=createWorkflowPublishHandler({publisher,enabled});
 return createAuthenticatedWorkflowGateway({resolveSession,publishHandler});
}
