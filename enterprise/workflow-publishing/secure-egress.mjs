// Trust-boundary HTTPS egress implementation. IPv4-only, DNS-pinned and
// fail-closed. NO endpoints configured, no automatic deployment.
import https from "node:https";
import dns from "node:dns/promises";
import {isIP,BlockList} from "node:net";
import {requireApprovedDestination} from "./signed-dispatch-envelope.mjs";
import {TransportError} from "./hardened-transport.mjs";
const deny=new BlockList();
for(const [network,prefix] of [
 ["0.0.0.0",8],["10.0.0.0",8],["100.64.0.0",10],["127.0.0.0",8],
 ["169.254.0.0",16],["172.16.0.0",12],["192.0.0.0",24],
 ["192.0.2.0",24],["192.168.0.0",16],["198.18.0.0",15],
 ["198.51.100.0",24],["203.0.113.0",24],["224.0.0.0",4],
 ["240.0.0.0",4]
])deny.addSubnet(network,prefix,"ipv4");
export function isAllowedPublicIPv4(address){
 return isIP(address)===4&&!deny.check(address,"ipv4");
}
export async function resolvePinnedIPv4(hostname,lookup=dns.lookup){
 const records=await lookup(hostname,{all:true,verbatim:true});
 if(!Array.isArray(records)||!records.length||
    records.some(r=>!r||r.family!==4||!isAllowedPublicIPv4(r.address)))
  throw new TransportError("DNS_ADDRESS_DENIED");
 return records[0].address;
}
export function createSecureEgressClient({allowedHosts,lookup=dns.lookup,request=https.request}={}){
 if(!Array.isArray(allowedHosts)||allowedHosts.length===0||
   typeof lookup!=="function"||typeof request!=="function")throw new TransportError("EGRESS_CONFIGURATION_INVALID");
 return Object.freeze({hardened:true,async send({url,method,headers,body,timeoutMs,maxResponseBytes,followRedirects}={}){
  const approved=requireApprovedDestination(url,allowedHosts);
  const parsed=new URL(approved);
  if(method!=="POST"||followRedirects!==false||
    !Number.isSafeInteger(timeoutMs)||timeoutMs<100||timeoutMs>30000||
    !Number.isSafeInteger(maxResponseBytes)||maxResponseBytes<256||maxResponseBytes>65536||
    typeof body!=="string"||Buffer.byteLength(body)>65536||
    !headers||typeof headers!=="object"||Array.isArray(headers))
    throw new TransportError("EGRESS_REQUEST_DENIED");
  const pinned=await resolvePinnedIPv4(parsed.hostname,lookup);
  const allowedHeaders={};
  for(const [key,value] of Object.entries(headers)){
   if(!/^(content-type|x-halo-key-id|x-halo-signature|x-halo-event-id|x-halo-issued-at|x-halo-nonce)$/i.test(key)||
      typeof value!=="string"||value.length>512||/[\r\n]/.test(value))
    throw new TransportError("EGRESS_HEADERS_DENIED");
   allowedHeaders[key]=value;
  }
  allowedHeaders["content-length"]=String(Buffer.byteLength(body));
  return await new Promise((resolve,reject)=>{
   let settled=false;
   const finish=(error,response)=>{if(settled)return;settled=true;error?reject(error):resolve(response);};
   const options={protocol:"https:",hostname:parsed.hostname,servername:parsed.hostname,
    port:443,path:parsed.pathname+parsed.search,method:"POST",headers:allowedHeaders,
    rejectUnauthorized:true,agent:false,
    lookup:(_host,_opts,callback)=>callback(null,pinned,4)};
   let req;
   try{req=request(options,res=>{
    let bytes=0;
    res.on("data",chunk=>{
     bytes+=Buffer.byteLength(chunk);
     if(bytes>maxResponseBytes){
      req.destroy(new TransportError("EGRESS_RESPONSE_TOO_LARGE"));
     }
    });
    res.on("end",()=>{
     if(res.statusCode>=300&&res.statusCode<400)
      finish(new TransportError("EGRESS_REDIRECT_DENIED"));
     else finish(null,{status:res.statusCode,responseBytes:bytes});
    });
    res.on("error",e=>finish(e));
   });}catch(e){finish(e);return;}
   req.setTimeout(timeoutMs,()=>req.destroy(new TransportError("EGRESS_TIMEOUT")));
   req.on("error",e=>finish(e));
   req.end(body);
  });
 }});
}
