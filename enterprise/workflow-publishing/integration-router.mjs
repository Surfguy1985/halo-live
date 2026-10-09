// Integration routing policy only. No network transport, secrets or live hooks.
// Registry MUST come from trusted server-side tenant configuration.
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
const types=new Set(["workflow.work_item.transitioned"]);
const allowedActions=new Set(["assign","accept","start","submit_evidence","request_review","approve","close"]);
export function planIntegrationDelivery({event,registrations}={}){
 if(!event||!id(event.eventID)||!id(event.tenantID)||!id(event.workItemID)||
  !types.has(event.type)||!allowedActions.has(event.action)||
  !Number.isSafeInteger(event.revision)||event.revision<1||
  !Array.isArray(registrations))throw TypeError("invalid routing inputs");
 const destinations=[];const seen=new Set();
 for(const registration of registrations){
  if(!registration||!id(registration.consumerID)||!id(registration.tenantID)||
   typeof registration.enabled!=="boolean"||!Array.isArray(registration.eventTypes)||
   !registration.eventTypes.every(x=>types.has(x))||
   !Array.isArray(registration.allowedActions)||!registration.allowedActions.every(x=>allowedActions.has(x)))
   throw TypeError("invalid trusted registration");
  if(registration.tenantID!==event.tenantID||!registration.enabled||
   !registration.eventTypes.includes(event.type)||
   !registration.allowedActions.includes(event.action))continue;
  if(seen.has(registration.consumerID))throw TypeError("duplicate consumer registration");
  seen.add(registration.consumerID);
  destinations.push(Object.freeze({tenantID:event.tenantID,eventID:event.eventID,
   consumerID:registration.consumerID,deliveryKey:registration.consumerID+":"+event.eventID}));
 }
 return Object.freeze(destinations);
}
