// Isolated in-process protection layer. For horizontally scaled deployments,
// replace the limiter with a shared atomic Redis/gateway implementation.
export function createRequestGuard({gateway,limit=30,windowMs=60_000,clock=()=>Date.now()}={}) {
 if(typeof gateway!=="function")throw TypeError("gateway required");
 const buckets=new Map();
 return async(req)=>{
  // Principal-level limits must be enforced after trusted authentication.
  // This coarse-grained guard uses connection-peer identity supplied by the HTTP
  // transport (NOT x-forwarded-for), and is not a replacement for edge protections.
  const peer=req.peerAddress;
  if(typeof peer!=="string"||!peer)return {status:400,body:JSON.stringify({error:"INVALID_PEER"})};
  const now=clock();
  if(buckets.size>10000)for(const [key,v] of buckets)if(v.reset<=now)buckets.delete(key);
  const current=buckets.get(peer);
  const bucket=!current||now>=current.reset?{count:0,reset:now+windowMs}:current;
  bucket.count++;
  buckets.set(peer,bucket);
  if(bucket.count>limit)return {status:429,body:JSON.stringify({error:"RATE_LIMITED"})};
  return gateway(req);
 };
}
