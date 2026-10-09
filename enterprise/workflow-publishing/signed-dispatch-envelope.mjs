// Pure outbound delivery envelope builder. NEVER performs HTTP or DNS lookup.
// Delivery secrets and destination policy are provided by trusted server adapters.
import {createHmac,randomUUID} from "node:crypto";
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class DispatchEnvelopeError extends Error {
 constructor(code){super(code);this.name="DispatchEnvelopeError";this.code=code;}
}
export function requireApprovedDestination(rawURL,allowedHosts){
 if(typeof rawURL!=="string"||rawURL.length>2048||!Array.isArray(allowedHosts)||
  allowedHosts.length<1||allowedHosts.length>32)throw new DispatchEnvelopeError("DESTINATION_DENIED");
 let u;try{u=new URL(rawURL);}catch{throw new DispatchEnvelopeError("DESTINATION_DENIED");}
 const host=u.hostname.toLowerCase();
 // Exact host allowlisting prevents suffix tricks; enforce transport egress
 // separately to stop DNS rebinding and redirects to private network targets.
 if(u.protocol!=="https:"||u.username||u.password||u.hash||u.port&&u.port!=="443"||
   !/^[a-z0-9][a-z0-9.-]*[a-z0-9]$/.test(host)||host==="localhost"||
   !allowedHosts.every(x=>typeof x==="string"&&x.length<=253)||
   !allowedHosts.some(x=>x.toLowerCase()===host))
  throw new DispatchEnvelopeError("DESTINATION_DENIED");
 return u.toString();
}
export function buildSignedDelivery({event,consumerID,destinationURL,allowedHosts,
 secret,keyID,issuedAt=Date.now(),nonce=randomUUID()}={}){
 if(!event||![event.eventID,event.tenantID,event.workItemID,consumerID,keyID,nonce].every(id)||
  !Number.isSafeInteger(event.revision)||event.revision<1||
  !["assign","accept","start","submit_evidence","request_review","approve","close"].includes(event.action)||
  event.type!=="workflow.work_item.transitioned"||
  !Number.isSafeInteger(issuedAt)||issuedAt<0||
  !(Buffer.isBuffer(secret)&&secret.length>=32))
  throw new DispatchEnvelopeError("INVALID_DELIVERY");
 const url=requireApprovedDestination(destinationURL,allowedHosts);
 const body=JSON.stringify({eventID:event.eventID,tenantID:event.tenantID,
  workItemID:event.workItemID,revision:event.revision,action:event.action,
  type:event.type,consumerID,issuedAt,nonce});
 const signature=createHmac("sha256",secret).update(body,"utf8").digest("hex");
 return Object.freeze({url,body,headers:Object.freeze({
  "content-type":"application/json",
  "x-halo-key-id":keyID,
  "x-halo-signature":"v1="+signature,
  "x-halo-event-id":event.eventID,
  "x-halo-issued-at":String(issuedAt),
  "x-halo-nonce":nonce
 })});
}
