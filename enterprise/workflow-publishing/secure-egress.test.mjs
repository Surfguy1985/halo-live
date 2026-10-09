import test from "node:test";
import assert from "node:assert/strict";
import {EventEmitter} from "node:events";
import {isAllowedPublicIPv4,resolvePinnedIPv4,createSecureEgressClient} from "./secure-egress.mjs";
const allowedHosts=["hooks.example.com"];
test("rejects RFC1918, loopback, metadata and documentation addresses",()=>{
 for(const ip of ["10.1.2.3","127.0.0.1","169.254.169.254","192.168.1.1","172.16.0.1","100.64.1.1","203.0.113.5","::1"])
  assert.equal(isAllowedPublicIPv4(ip),false,ip);
 assert.equal(isAllowedPublicIPv4("8.8.8.8"),true);
});
test("rejects mixed DNS answers or IPv6 and pins public IPv4",async()=>{
 await assert.rejects(()=>resolvePinnedIPv4("hooks.example.com",async()=>[{address:"8.8.8.8",family:4},{address:"127.0.0.1",family:4}]),/DNS_ADDRESS_DENIED/);
 await assert.rejects(()=>resolvePinnedIPv4("hooks.example.com",async()=>[{address:"2001:4860:4860::8888",family:6}]),/DNS_ADDRESS_DENIED/);
 assert.equal(await resolvePinnedIPv4("hooks.example.com",async()=>[{address:"8.8.8.8",family:4}]),"8.8.8.8");
});
test("pins DNS lookup, TLS and disallows redirects in request options",async()=>{
 let captured;const fake=(options,cb)=>{
  captured=options;const req=new EventEmitter();
  req.setTimeout=()=>{};req.end=()=>{
   const res=new EventEmitter();res.statusCode=204;cb(res);
   queueMicrotask(()=>res.emit("end"));
  };req.destroy=e=>req.emit("error",e);return req;
 };
 const client=createSecureEgressClient({allowedHosts,lookup:async()=>[{address:"8.8.8.8",family:4}],request:fake});
 const r=await client.send({url:"https://hooks.example.com/event",method:"POST",
  headers:{"x-halo-signature":"v1=abc"},body:"{}",timeoutMs:5000,maxResponseBytes:1024,followRedirects:false});
 assert.deepEqual(r,{status:204,responseBytes:0});
 assert.equal(captured.rejectUnauthorized,true);assert.equal(captured.agent,false);
 assert.equal(captured.servername,"hooks.example.com");
 assert.equal(captured.lookup("hooks.example.com",{},(err,ip,family)=>{assert.equal(ip,"8.8.8.8");assert.equal(family,4);}),undefined);
});
test("rejects unauthorised target or unsafe header before sending",async()=>{
 let calls=0;const fake=()=>{calls++;throw Error("should not send");};
 const client=createSecureEgressClient({allowedHosts,lookup:async()=>[{address:"8.8.8.8",family:4}],request:fake});
 const base={url:"https://hooks.example.com/event",method:"POST",headers:{"x-halo-signature":"v1=abc"},body:"{}",timeoutMs:5000,maxResponseBytes:1024,followRedirects:false};
 await assert.rejects(()=>client.send({...base,url:"https://evil.com/event"}));
 await assert.rejects(()=>client.send({...base,headers:{"authorization":"Bearer secret"}}));
 assert.equal(calls,0);
});
