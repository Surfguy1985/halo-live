// Server-only authorization boundary for integration subscription configuration.
// Actor context must be issued by verified middleware, never request JSON.
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
const events=new Set(["workflow.work_item.transitioned"]);
const actions=new Set(["assign","accept","start","submit_evidence","request_review","approve","close"]);
export class RegistryError extends Error {constructor(code){super(code);this.name="RegistryError";this.code=code;}}
export function authorizeRegistryChange({session,tenantID,consumerID,expectedRevision,subscription}={}){
 if(!session?.authenticated||!id(session.actorID)||!id(session.tenantID)||
  !Array.isArray(session.permissions)||!session.permissions.includes("integrations:manage"))
  throw new RegistryError("FORBIDDEN");
 if(!id(tenantID)||session.tenantID!==tenantID)throw new RegistryError("FORBIDDEN_SCOPE");
 if(!id(consumerID)||!Number.isSafeInteger(expectedRevision)||expectedRevision<0)
  throw new RegistryError("INVALID_REQUEST");
 if(!subscription||typeof subscription!=="object"||Array.isArray(subscription)||
  Object.keys(subscription).some(x=>!["enabled","eventTypes","allowedActions"].includes(x))||
  typeof subscription.enabled!=="boolean"||
  !Array.isArray(subscription.eventTypes)||subscription.eventTypes.length>16||
  !subscription.eventTypes.every(x=>events.has(x))||
  new Set(subscription.eventTypes).size!==subscription.eventTypes.length||
  !Array.isArray(subscription.allowedActions)||subscription.allowedActions.length>32||
  !subscription.allowedActions.every(x=>actions.has(x))||
  new Set(subscription.allowedActions).size!==subscription.allowedActions.length)
  throw new RegistryError("INVALID_SUBSCRIPTION");
 return Object.freeze({tenantID,consumerID,expectedRevision,actorID:session.actorID,
  subscription:Object.freeze({enabled:subscription.enabled,eventTypes:Object.freeze([...subscription.eventTypes]),
   allowedActions:Object.freeze([...subscription.allowedActions])})});
}
