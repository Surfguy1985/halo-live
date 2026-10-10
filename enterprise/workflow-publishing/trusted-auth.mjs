// Isolated trusted session boundary. NOT mounted to live API.
// Identity verification is performed by the injected backend verifier.
// Never trust tenant, industry or permissions supplied in the request JSON.
const valid = s => typeof s === "string" && s.length > 0 && s.length <= 128;
const idSet = xs => Array.isArray(xs) && xs.every(valid) && xs.length <= 128;
export class AuthenticationError extends Error {
  constructor() { super("Authentication required"); this.code="UNAUTHENTICATED"; }
}
export class AuthorizationError extends Error {
  constructor() { super("Access denied"); this.code="FORBIDDEN"; }
}
export function createTrustedSessionResolver({verifyBearer,loadMembership}={}) {
  if (typeof verifyBearer!=="function" || typeof loadMembership!=="function")
    throw new TypeError("Trusted identity verifier and membership loader required");
  return async function resolve(headers) {
    const authorization=headers?.authorization;
    if (typeof authorization!=="string" || !/^Bearer [A-Za-z0-9._~+\/-]+=*$/.test(authorization))
      throw new AuthenticationError();
    // Verifier must check issuer, audience, signature, expiry and revocation policy.
    const identity=await verifyBearer(authorization.slice(7));
    if (!identity || !valid(identity.subject)) throw new AuthenticationError();
    // Membership loader must retrieve CURRENT membership from trusted storage.
    const membership=await loadMembership(identity.subject);
    if (!membership || membership.active!==true || !valid(membership.tenantID) ||
        !idSet(membership.industryIDs) || !idSet(membership.permissions))
      throw new AuthorizationError();
    return Object.freeze({
      authenticated:true,actorID:identity.subject,tenantID:membership.tenantID,
      industryIDs:Object.freeze([...membership.industryIDs]),
      permissions:Object.freeze([...membership.permissions])
    });
  };
}
// Framework-neutral adapter. Middleware owns request lifecycle and error translation.
export function createAuthenticatedWorkflowGateway({resolveSession,publishHandler,reconcileHandler}={}) {
  if (typeof resolveSession!=="function" || typeof publishHandler!=="function")
    throw new TypeError("Resolver and publish handler required");
  return async function handle(request) {
    let session;
    try { session=await resolveSession(request?.headers); }
    catch(error) {
      if (error instanceof AuthorizationError) return {status:403,body:JSON.stringify({error:"FORBIDDEN"})};
      return {status:401,body:JSON.stringify({error:"UNAUTHENTICATED"})};
    }
    if (typeof request?.path==="string" && request.path.endsWith("/reconcile"))
      return typeof reconcileHandler==="function" ? reconcileHandler(request,session) :
        {status:404,body:JSON.stringify({error:"NOT_FOUND"})};
    return publishHandler(request,session);
  };
}
