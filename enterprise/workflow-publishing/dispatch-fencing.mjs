// Revocation-aware send permit protocol. No external network transport.
// Authority must be backed by a trusted, durable registry and lease database.
import {authorizeDeliveryNow} from "./dispatch-authorization.mjs";
const valid=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class DispatchPermitError extends Error{constructor(code){super(code);this.code=code;}}
export class FencedDispatchCoordinator{
 constructor({registry,permits}){
  if(typeof registry?.lookup!=="function"||typeof permits?.issue!=="function"||
    typeof permits?.validate!=="function"||typeof permits?.invalidateConsumer!=="function")
   throw TypeError("trusted registry/permit adapters required");
  this.registry=registry;this.permits=permits;
 }
 async issue(delivery){
  const decision=await authorizeDeliveryNow({delivery,registry:this.registry});
  if(!decision.authorized)throw new DispatchPermitError(decision.reason);
  const result=await this.permits.issue({delivery,registrationRevision:decision.registrationRevision});
  if(!result||!valid(result.permitID)||!Number.isSafeInteger(result.registrationRevision)||
   result.registrationRevision!==decision.registrationRevision)throw new DispatchPermitError("PERMIT_REJECTED");
  return Object.freeze({...result});
 }
 async validateForSend({delivery,permit}){
  if(!permit||!valid(permit.permitID))return false;
  const result=await this.permits.validate({delivery,permit});
  if(result!==true)return false;
  const current=await authorizeDeliveryNow({delivery,registry:this.registry});
  return current.authorized && current.registrationRevision===permit.registrationRevision;
 }
 async revoke({tenantID,consumerID,revision}){
  if(!valid(tenantID)||!valid(consumerID)||!Number.isSafeInteger(revision)||revision<1)
   throw new DispatchPermitError("INVALID_REVOCATION");
  return this.permits.invalidateConsumer({tenantID,consumerID,revision});
 }
}
