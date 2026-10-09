// Transactional per-consumer fanout planner. No network calls or live wiring.
import {planIntegrationDelivery} from "./integration-router.mjs";
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export async function fanoutCommittedEvent({event,registrations,store}={}){
 if(!store||typeof store.transaction!=="function")throw TypeError("transaction store required");
 const destinations=planIntegrationDelivery({event,registrations});
 // Only an internal dispatcher may call this function; store.transaction MUST
 // verify committed event identity, tenant and scope before inserting rows.
 return store.transaction(event.tenantID,event.eventID,async tx=>{
  if(typeof tx.verifyCommittedEvent!=="function"||typeof tx.insertDeliveryIfAbsent!=="function")
   throw TypeError("tenant-scoped transaction methods required");
  const committed=await tx.verifyCommittedEvent(event);
  if(committed!==true)throw Error("EVENT_NOT_COMMITTED_OR_SCOPE_MISMATCH");
  let inserted=0;
  for(const destination of destinations){
   if(!id(destination.consumerID)||destination.tenantID!==event.tenantID)
    throw Error("UNAUTHORIZED_DESTINATION");
   if(await tx.insertDeliveryIfAbsent(destination))inserted++;
  }
  return Object.freeze({tenantID:event.tenantID,eventID:event.eventID,eligible:destinations.length,inserted});
 });
}
