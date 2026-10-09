// Fail-closed delivery outcome protocol. Transport timeout is UNKNOWN, not failure.
// Adapters must durably CAS lease+permit and persist receipt atomically.
const id = x => typeof x==="string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class DeliveryReliabilityError extends Error {
 constructor(code){super(code);this.name="DeliveryReliabilityError";this.code=code;}
}
export function requireBoundLease({delivery,lease,permit}={}){
 if(!delivery||![delivery.tenantID,delivery.consumerID,delivery.eventID].every(id)||
  !lease||![lease.workerID,lease.leaseToken].every(id)||
  !permit||!id(permit.permitID)||
  !Number.isSafeInteger(permit.registrationRevision)||permit.registrationRevision<1||
  lease.tenantID!==delivery.tenantID||lease.consumerID!==delivery.consumerID||
  lease.eventID!==delivery.eventID||
  permit.tenantID!==delivery.tenantID||permit.consumerID!==delivery.consumerID||
  permit.eventID!==delivery.eventID||
  permit.leaseToken!==lease.leaseToken)
  throw new DeliveryReliabilityError("LEASE_PERMIT_BINDING_DENIED");
 return Object.freeze({tenantID:delivery.tenantID,consumerID:delivery.consumerID,
  eventID:delivery.eventID,workerID:lease.workerID,leaseToken:lease.leaseToken,
  permitID:permit.permitID,registrationRevision:permit.registrationRevision});
}
export function classifyObservedDelivery({response,error}={}){
 if(error){
  // Socket failures and timeouts cannot prove that a remote server did not
  // perform the side effect. Even a response read failure is ambiguous.
  return Object.freeze({state:"uncertain",reason:"NETWORK_OUTCOME_UNKNOWN"});
 }
 if(!response||!Number.isInteger(response.httpStatus))
  return Object.freeze({state:"uncertain",reason:"MISSING_ACK"});
 if(response.httpStatus>=200&&response.httpStatus<300)
  return Object.freeze({state:"acknowledged",reason:"HTTP_2XX"});
 if(response.httpStatus===408||response.httpStatus===425||
  response.httpStatus===429||response.httpStatus>=500&&response.httpStatus<=599)
  return Object.freeze({state:"uncertain",reason:"UPSTREAM_MAY_HAVE_PROCESSED"});
 return Object.freeze({state:"rejected",reason:"UPSTREAM_REJECTED"});
}
export async function recordDeliveryOutcome({store,delivery,lease,permit,response,error}={}){
 if(typeof store?.commitOutcome!=="function")
  throw new DeliveryReliabilityError("DURABLE_STORE_REQUIRED");
 const binding=requireBoundLease({delivery,lease,permit});
 const outcome=classifyObservedDelivery({response,error});
 const committed=await store.commitOutcome({...binding,outcome});
 if(committed!==true)throw new DeliveryReliabilityError("LEASE_LOST_OR_OUTCOME_CONFLICT");
 return outcome;
}
