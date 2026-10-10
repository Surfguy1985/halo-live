import net from "node:net";

const deny=()=>{throw new Error("HALO CI Redis adapter denied");};
const encode=parts=>{
 if(!Array.isArray(parts)||parts.length<1||parts.some(value=>typeof value!=="string"||value.length>65536))deny();
 return Buffer.concat([Buffer.from(`*${parts.length}\r\n`),...parts.flatMap(value=>{
  const data=Buffer.from(value);
  return [Buffer.from(`$${data.length}\r\n`),data,Buffer.from("\r\n")];
 })]);
};

export function parseCIStagingRedisResponse(buffer){
 if(!Buffer.isBuffer(buffer)||buffer.length<3)return undefined;
 const end=buffer.indexOf("\r\n");
 if(end<0)return undefined;
 const type=String.fromCharCode(buffer[0]);
 const line=buffer.subarray(1,end).toString("utf8");
 if(type==="+")return {value:line,bytes:end+2};
 if(type==="-")throw new Error("Redis error: "+line.slice(0,200));
 if(type===":"){
  const value=Number(line);if(!Number.isSafeInteger(value))deny();
  return {value,bytes:end+2};
 }
 if(type==="$" ){
  const length=Number(line);if(!Number.isSafeInteger(length)||length<0||length>1048576)deny();
  const last=end+2+length;
  if(buffer.length<last+2)return undefined;
  if(buffer[last]!==13||buffer[last+1]!==10)deny();
  return {value:buffer.subarray(end+2,last).toString("utf8"),bytes:last+2};
 }
 deny();
}

async function requestRedis(host,port,parts){
 return new Promise((resolve,reject)=>{
  const socket=net.createConnection({host,port});
  let received=Buffer.alloc(0),finished=false;
  const finish=(error,value)=>{
   if(finished)return;finished=true;socket.destroy();
   error?reject(error):resolve(value);
  };
  socket.setTimeout(1500,()=>finish(new Error("Redis timeout")));
  socket.once("error",error=>finish(error));
  socket.once("connect",()=>socket.write(encode(parts)));
  socket.on("data",chunk=>{
   received=Buffer.concat([received,chunk]);
   if(received.length>1048576)return finish(new Error("Redis response too large"));
   try{const parsed=parseCIStagingRedisResponse(received);if(parsed)finish(undefined,parsed.value);}
   catch(error){finish(error);}
  });
  socket.once("end",()=>finish(new Error("Redis closed before response")));
 });
}

export function createCIStagingRedis({url,request=requestRedis}={}){
 let target;
 try{target=new URL(url);}catch{deny();}
 if(target.href!=="redis://127.0.0.1:6379/0" || typeof request!=="function")deny();
 const call=parts=>request("127.0.0.1",6379,parts);
 return Object.freeze({
  async ping(){return call(["PING"]);},
  async eval(script,{keys=[],arguments:args=[]}={}){
   if(!Array.isArray(keys)||!Array.isArray(args))deny();
   return call(["EVAL",script,String(keys.length),...keys,...args]);
  }
 });
}

export {encode as encodeCIStagingRedisCommand};
