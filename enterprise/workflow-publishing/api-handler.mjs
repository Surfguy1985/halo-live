// Isolated HTTP transport adapter. NOT mounted into an application.
// The caller MUST provide a verified, server-issued session; never source it
// from a body, cookie string, user-supplied header or unsigned token.
import { PublishError } from "./publisher.mjs";

const LIMIT_BYTES = 128 * 1024;
const templatePath = /^\/v1\/workflow-templates\/([a-zA-Z0-9_-]{1,128})\/publish$/;
const jsonResponse = (status, payload) => ({
  status, headers: {"content-type":"application/json","cache-control":"no-store"}, body:JSON.stringify(payload)
});
const token = value => typeof value==="string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const object = value => value !== null && typeof value==="object" && !Array.isArray(value);
const statusFor = error => ({
  FORBIDDEN:403, INVALID:422, REVISION_CONFLICT:409, IDEMPOTENCY_CONFLICT:409
})[error.code] ?? 500;

/**
 * Framework-neutral gateway for the workflow-publishing service.
 * Request shape: {method,path,headers,body}, body is a string or Buffer.
 * The HTTP server is responsible for trusted authentication, request deadlines,
 * TLS, CSRF protections where cookie auth is used, rate limits, and telemetry.
 */
export function createWorkflowPublishHandler({publisher, enabled=false}={}) {
  if (!publisher || typeof publisher.publish !== "function") throw new TypeError("publisher required");
  return async function publish(request, verifiedSession) {
    if (!enabled) return jsonResponse(404,{error:"NOT_FOUND"});
    const match = typeof request?.path==="string" && request.path.match(templatePath);
    if (!match) return jsonResponse(404,{error:"NOT_FOUND"});
    if (request.method!=="POST") return jsonResponse(405,{error:"METHOD_NOT_ALLOWED"});
    // The HTTP framework must normalize header names, including duplicate
    // Idempotency-Key headers, before calling this adapter.
    if (!request.headers || request.headers["content-type"]?.split(";")[0]?.trim().toLowerCase() !== "application/json")
      return jsonResponse(415,{error:"UNSUPPORTED_MEDIA_TYPE"});
    if (!verifiedSession?.authenticated || !verifiedSession.actorID || !verifiedSession.tenantID ||
        !Array.isArray(verifiedSession.permissions) ||
        !verifiedSession.permissions.includes("workflow:publish"))
      return jsonResponse(403,{error:"FORBIDDEN"});
    const key=request.headers["idempotency-key"];
    // A revision must never be negative; reject invalid proposals before storage.
    if (!token(key)) return jsonResponse(422,{error:"INVALID_IDEMPOTENCY_KEY"});
    if (typeof request.body!=="string" && !Buffer.isBuffer(request.body))
      return jsonResponse(422,{error:"INVALID_BODY"});
    const raw=Buffer.isBuffer(request.body)?request.body:Buffer.from(request.body,"utf8");
    if (raw.byteLength>LIMIT_BYTES) return jsonResponse(413,{error:"PAYLOAD_TOO_LARGE"});
    let parsed;
    try {parsed=JSON.parse(raw.toString("utf8"));} catch {return jsonResponse(400,{error:"INVALID_JSON"});}
    if (!object(parsed) || !token(parsed.requestID) || parsed.requestID!==key ||
        !object(parsed.layout) || !Number.isSafeInteger(parsed.expectedRevision) || parsed.expectedRevision < 0)
      return jsonResponse(422,{error:"INVALID_REQUEST"});
    try {
      const result=await publisher.publish({
        session:verifiedSession,templateID:match[1],idempotencyKey:key,
        proposal:{expectedRevision:parsed.expectedRevision,layout:parsed.layout}
      });
      return jsonResponse(200,result);
    } catch (error) {
      if (error instanceof PublishError)
        return jsonResponse(statusFor(error),{error:error.code});
      // Fail closed. Never echo SQL errors or internal exception messages.
      return jsonResponse(500,{error:"INTERNAL"});
    }
  };
}
