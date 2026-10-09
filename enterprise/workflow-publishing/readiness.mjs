// Dependency readiness probe. Intended for trusted internal load balancers.
// No customer data or error internals are surfaced in its boolean result.
export function createWorkflowReadiness({postgres,redis,timeoutMs=1500}={}) {
 if(!postgres||typeof postgres.query!=="function"||!redis||typeof redis.ping!=="function")
  throw new TypeError("PostgreSQL and Redis probes required");
 return async ()=>{
  const probe=async fn=> {
   let timer;
   try {return await Promise.race([fn(),new Promise((_,reject)=>{
    timer=setTimeout(()=>reject(Error("timeout")),timeoutMs);
   })]);} finally {clearTimeout(timer);}
  };
  try {
   const [db,cache]=await Promise.all([
    probe(()=>postgres.query("SELECT 1 AS ready")),
    probe(()=>redis.ping())
   ]);
   return db?.rows?.[0]?.ready===1 && cache==="PONG";
  }catch{return false;}
 };
}
