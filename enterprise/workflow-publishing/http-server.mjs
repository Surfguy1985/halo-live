// Isolated Node HTTP adapter. Never started automatically; no live deployment.
import http from "node:http";
const MAX_BODY=128*1024;
const response=(res,status,body)=>{res.writeHead(status,{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff"});res.end(JSON.stringify(body));};
export function createWorkflowHTTPServer({gateway,enabled=false}={}) {
 if(typeof gateway!=="function")throw new TypeError("gateway required");
 return http.createServer(async(req,res)=>{
  if(!enabled){response(res,404,{error:"NOT_FOUND"});return;}
  const path=req.url?.split("?")[0]??"";
  if(!/^\/v1\/workflow-templates\/[a-zA-Z0-9_-]{1,128}\/publish$/.test(path)){
   response(res,404,{error:"NOT_FOUND"});return;
  }
  if(req.method!=="POST"){response(res,405,{error:"METHOD_NOT_ALLOWED"});return;}
  const contentLength=Number(req.headers["content-length"]);
  if(Number.isFinite(contentLength)&&contentLength>MAX_BODY){
   response(res,413,{error:"PAYLOAD_TOO_LARGE"});req.resume();return;
  }
  let size=0;const chunks=[];
  try {
   for await(const chunk of req){
    size+=chunk.byteLength;
    if(size>MAX_BODY){response(res,413,{error:"PAYLOAD_TOO_LARGE"});req.destroy();return;}
    chunks.push(chunk);
   }
   const result=await gateway({method:req.method,path,headers:req.headers,body:Buffer.concat(chunks)});
   const status=Number.isInteger(result?.status)&&result.status>=400&&result.status<=599||result?.status===200?result.status:500;
   res.writeHead(status,{"content-type":"application/json","cache-control":"no-store","x-content-type-options":"nosniff"});
   res.end(typeof result?.body==="string"?result.body:JSON.stringify({error:"INTERNAL"}));
  }catch{
   if(!res.headersSent) response(res,500,{error:"INTERNAL"});
   else res.destroy();
  }
 });
}
