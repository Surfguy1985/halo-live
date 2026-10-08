import {randomUUID} from "node:crypto";
// Server-issued IDs only. Never log bearer tokens, request bodies, or customer IDs.
export function createObservability({logger=()=>{},clock=()=>Date.now()}={}) {
 const metrics={requests:0,errors:0,rateLimited:0};
 return {
  metrics,
  wrap(gateway){
   if(typeof gateway!=="function")throw TypeError("gateway required");
   return async req=>{
    const correlationID=randomUUID(),start=clock();
    metrics.requests++;
    let result;
    try {result=await gateway({...req,correlationID});}
    catch {result={status:500,body:JSON.stringify({error:"INTERNAL"})};}
    const status=Number.isInteger(result?.status)?result.status:500;
    if(status>=500)metrics.errors++;
    if(status===429)metrics.rateLimited++;
    try {logger({event:"halo.workflow.http",correlationID,status,
      durationMs:Math.max(0,clock()-start),method:req.method,
      route:"workflow.publish"});} catch {/* logs never break requests */}
    return {...result,headers:{...result?.headers,"x-correlation-id":correlationID}};
   };
  },
  snapshot(){return {...metrics};}
 };
}
