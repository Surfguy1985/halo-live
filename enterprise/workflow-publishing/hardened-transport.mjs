// Transport policy wrapper. NO default network client or credential loading.
// Production connector must inject an audited egress client enforcing DNS pinning,
// public-address policy, TLS verification and no proxy/redirect bypass.
export class TransportError extends Error {
 constructor(code){super(code);this.name="TransportError";this.code=code;}
}
export function classifyDeliveryStatus(status){
 if(status>=200&&status<300)return "delivered";
 if(status===408||status===425||status===429||status>=500&&status<=599)return "retryable";
 return "permanent";
}
export function createHardenedTransport({egressClient,timeoutMs=5000,maxResponseBytes=16384}={}){
 if(typeof egressClient?.send!=="function"||egressClient.hardened!==true)
  throw new TransportError("HARDENED_EGRESS_REQUIRED");
 if(!Number.isSafeInteger(timeoutMs)||timeoutMs<100||timeoutMs>30000||
  !Number.isSafeInteger(maxResponseBytes)||maxResponseBytes<256||maxResponseBytes>65536)
  throw new TransportError("INVALID_LIMITS");
 return Object.freeze({async deliver(envelope){
  if(!envelope||typeof envelope.url!=="string"||typeof envelope.body!=="string"||
   Buffer.byteLength(envelope.body)>65536||!envelope.headers||
   !envelope.headers["x-halo-signature"])
   throw new TransportError("INVALID_ENVELOPE");
  // No fetch() fallback: egressClient owns DNS and TLS policy end-to-end.
  const response=await egressClient.send({url:envelope.url,method:"POST",
   headers:envelope.headers,body:envelope.body,timeoutMs,maxResponseBytes,
   followRedirects:false});
  if(!response||!Number.isInteger(response.status)||
   response.status<100||response.status>599||
   !Number.isSafeInteger(response.responseBytes)||response.responseBytes<0||
   response.responseBytes>maxResponseBytes)
   throw new TransportError("EGRESS_POLICY_VIOLATION");
  const result=classifyDeliveryStatus(response.status);
  if(result==="delivered")return Object.freeze({status:"delivered",httpStatus:response.status});
  throw new TransportError(result==="retryable"?"UPSTREAM_RETRYABLE":"UPSTREAM_PERMANENT");
 }});
}
