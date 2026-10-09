// Isolated outbox worker. No network transport, webhook URLs or live hooks.
// Lease/finalization methods MUST be implemented atomically by a durable adapter.
const valid=x=>typeof x==="string"&&/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(x);
export function createOutboxWorker({store,deliver,consumerID,workerID,clock=()=>Date.now(),maxAttempts=8,leaseMs=30000}={}){
 if(!store||typeof store.claim!=="function"||typeof store.complete!=="function"||typeof store.retry!=="function"||typeof store.deadLetter!=="function")throw TypeError("durable outbox adapter required");
 if(typeof deliver!=="function"||!valid(consumerID)||!valid(workerID))throw TypeError("trusted consumer and worker required");
 if(!Number.isSafeInteger(maxAttempts)||maxAttempts<1||maxAttempts>100||!Number.isSafeInteger(leaseMs)||leaseMs<1000)throw TypeError("invalid worker limits");
 return Object.freeze({async tick(){
  const now=clock();const event=await store.claim({consumerID,workerID,now,leaseMs});
  if(!event)return {status:"idle"};
  if(!valid(event.eventID)||!valid(event.tenantID)||!valid(event.workItemID)||!Number.isSafeInteger(event.attempts)||event.attempts<1)
   throw Error("invalid leased event");
  const identity={eventID:event.eventID,consumerID,workerID,leaseToken:event.leaseToken};
  try{
   // Each consumer must deduplicate using (consumerID,eventID). A timeout after
   // remote success cannot be resolved by the sender alone.
   await deliver({eventID:event.eventID,tenantID:event.tenantID,workItemID:event.workItemID,revision:event.revision,action:event.action,consumerID});
   const completed=await store.complete({...identity,now:clock()});
   return {status:completed?"delivered":"lease_lost",eventID:event.eventID};
  }catch(error){
   const code=typeof error?.code==="string"&&valid(error.code)?error.code:"DELIVERY_FAILED";
   if(event.attempts>=maxAttempts){
    const done=await store.deadLetter({...identity,now:clock(),errorCode:code});
    return {status:done?"dead_letter":"lease_lost",eventID:event.eventID};
   }
   const delayMs=Math.min(3_600_000,1000*2**Math.min(12,event.attempts-1));
   const done=await store.retry({...identity,now:clock(),availableAt:clock()+delayMs,errorCode:code});
   return {status:done?"retry_scheduled":"lease_lost",eventID:event.eventID,delayMs};
  }
 }});
}
