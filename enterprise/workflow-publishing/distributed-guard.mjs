// Redis-backed distributed fixed-window limiter. Isolated, never enabled automatically.
// Atomically count and expire using a Lua script; do not trust X-Forwarded-For.
const SCRIPT=`
local n=redis.call('INCR',KEYS[1])
if n==1 then redis.call('PEXPIRE',KEYS[1],ARGV[1]) end
return n
`;
export function createDistributedRequestGuard({gateway,redis,limit=60,windowMs=60000,clock=()=>Date.now(),prefix="halo:workflow:rl"}={}) {
 if(typeof gateway!=="function" || !redis || typeof redis.eval!=="function" ||
  !Number.isSafeInteger(limit)||limit<1||!Number.isSafeInteger(windowMs)||windowMs<1000)
  throw new TypeError("Invalid limiter configuration");
 return async request=>{
  const peer=request?.peerAddress;
  if(typeof peer!=="string"||!peer||peer.length>256)return {status:400,body:JSON.stringify({error:"INVALID_PEER"})};
  const bucket=Math.floor(clock()/windowMs);
  // Peer never interpolated as a raw Redis key; deterministic short hash.
  const {createHash}=await import("node:crypto");
  const id=createHash("sha256").update(peer).digest("hex");
  try {
   const count=Number(await redis.eval(SCRIPT,{keys:[prefix+":"+bucket+":"+id],arguments:[String(windowMs+1000)]}));
   if(!Number.isSafeInteger(count)||count<1)throw Error("Invalid limiter response");
   if(count>limit)return {status:429,body:JSON.stringify({error:"RATE_LIMITED"})};
  }catch {
   // Deny instead of removing rate protection on Redis failure.
   return {status:503,body:JSON.stringify({error:"RATE_LIMIT_UNAVAILABLE"})};
  }
  return gateway(request);
 };
}
