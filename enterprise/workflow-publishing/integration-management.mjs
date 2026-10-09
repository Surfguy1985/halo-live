// Isolated registration mutation orchestrator. No HTTP route or live credentials.
import {authorizeRegistryChange,RegistryError} from "./integration-registry.mjs";
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class IntegrationManagementService {
 constructor(store){if(typeof store?.transaction!=="function")throw TypeError("transaction store required");this.store=store;}
 async update({session,tenantID,consumerID,expectedRevision,subscription,requestID}={}){
  const proposal=authorizeRegistryChange({session,tenantID,consumerID,expectedRevision,subscription});
  if(!id(requestID))throw new RegistryError("INVALID_REQUEST");
  return this.store.transaction(tenantID,consumerID,async tx=>{
   const previous=await tx.getReceipt(requestID);
   if(previous){
    if(previous.expectedRevision!==expectedRevision || JSON.stringify(previous.subscription)!==JSON.stringify(proposal.subscription))
     throw new RegistryError("IDEMPOTENCY_CONFLICT");
    return previous.result;
   }
   const current=await tx.getLockedRegistration();
   if((current?.revision??0)!==expectedRevision)throw new RegistryError("REVISION_CONFLICT");
   const revision=expectedRevision+1;
   if(!Number.isSafeInteger(revision))throw new RegistryError("REVISION_CONFLICT");
   await tx.upsertRegistration({...proposal.subscription,revision});
   const result=Object.freeze({tenantID,consumerID,revision,enabled:proposal.subscription.enabled});
   await tx.appendAudit({tenantID,consumerID,actorID:session.actorID,revision,
    action:proposal.subscription.enabled?"integration.updated":"integration.revoked",requestID});
   await tx.saveReceipt(requestID,{expectedRevision,subscription:proposal.subscription,result});
   return result;
  });
 }
}
