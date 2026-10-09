// Isolated, off-by-default dispatch orchestration. No worker scheduler or secrets.
// Trusted adapters must enforce membership, current lease and permit issuance.
import {buildSignedDelivery} from "./signed-dispatch-envelope.mjs";
import {createHardenedTransport} from "./hardened-transport.mjs";
import {authorizeDeliveryNow} from "./dispatch-authorization.mjs";
export class DispatchPipelineError extends Error{constructor(code){super(code);this.code=code;}}
export function createDispatchPipeline({enabled=false,registry,leaseVerifier,permitGateway,secretProvider,egressClient,allowedHosts}={}){
 if(enabled!==true)throw new DispatchPipelineError("DISPATCH_DISABLED");
 if(typeof registry?.lookup!=="function"||typeof leaseVerifier?.verify!=="function"||
  typeof permitGateway?.authorizeSend!=="function"||typeof secretProvider?.get!=="function")
  throw new DispatchPipelineError("TRUSTED_ADAPTERS_REQUIRED");
 const transport=createHardenedTransport({egressClient});
 return Object.freeze({async deliver({delivery,permit,now}={}){
  if(!delivery||!permit)throw new DispatchPipelineError("INVALID_DELIVERY");
  const leaseValid=await leaseVerifier.verify(delivery);
  if(leaseValid!==true)throw new DispatchPipelineError("LEASE_DENIED");
  const registration=await authorizeDeliveryNow({delivery,registry});
  if(!registration.authorized)throw new DispatchPipelineError(registration.reason);
  if(registration.registrationRevision!==permit.registrationRevision)
   throw new DispatchPipelineError("REGISTRATION_CHANGED");
  // The gateway consumes the single-use DB permit. Never retry a consumed
  // permit: retry must obtain a new trusted lease and permit.
  await permitGateway.authorizeSend({tenantID:delivery.tenantID,consumerID:delivery.consumerID,
   eventID:delivery.eventID,permitID:permit.permitID,
   registrationRevision:permit.registrationRevision,now});
  const credential=await secretProvider.get({tenantID:delivery.tenantID,consumerID:delivery.consumerID});
  if(!credential||!credential.secret||!credential.keyID||!credential.destinationURL)
   throw new DispatchPipelineError("CREDENTIAL_UNAVAILABLE");
  const envelope=buildSignedDelivery({event:delivery,consumerID:delivery.consumerID,
   destinationURL:credential.destinationURL,allowedHosts,secret:credential.secret,
   keyID:credential.keyID,issuedAt:now});
  return transport.deliver(envelope);
 }});
}
