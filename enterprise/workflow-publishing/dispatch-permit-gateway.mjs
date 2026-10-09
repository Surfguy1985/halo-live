// Trusted, single-use permit consumption protocol; gateway adapter executes
// consume atomically alongside current registry revision verification.
// This is an isolated contract, not a network-enabled gateway.
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class PermitError extends Error{constructor(code){super(code);this.code=code;}}
export class DispatchPermitGateway{
 constructor(store){if(typeof store?.consumeIfAuthorized!=="function")throw TypeError("trusted permit store required");this.store=store;}
 async authorizeSend({tenantID,consumerID,eventID,permitID,registrationRevision,now=Date.now()}={}){
  if(![tenantID,consumerID,eventID,permitID].every(id)||
   !Number.isSafeInteger(registrationRevision)||registrationRevision<1||
   !Number.isSafeInteger(now)||now<0)throw new PermitError("INVALID_PERMIT_REQUEST");
  const outcome=await this.store.consumeIfAuthorized({tenantID,consumerID,eventID,permitID,registrationRevision,now});
  if(outcome!==true)throw new PermitError("PERMIT_EXPIRED_REVOKED_OR_REPLAYED");
  return Object.freeze({authorized:true,tenantID,consumerID,eventID,permitID});
 }
}
