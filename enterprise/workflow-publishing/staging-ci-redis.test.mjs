import test from "node:test";
import assert from "node:assert/strict";
import {createCIStagingRedis,encodeCIStagingRedisCommand,parseCIStagingRedisResponse}
 from "./staging-ci-redis.mjs";

test("encodes Redis commands without shell or string interpolation",()=>{
 assert.equal(encodeCIStagingRedisCommand(["PING"]).toString(),"*1\r\n$4\r\nPING\r\n");
 assert.equal(encodeCIStagingRedisCommand(["EVAL","return 1","0"]).toString(),
  "*3\r\n$4\r\nEVAL\r\n$8\r\nreturn 1\r\n$1\r\n0\r\n");
});

test("parses only bounded simple, integer and bulk responses",()=>{
 assert.deepEqual(parseCIStagingRedisResponse(Buffer.from("+PONG\r\n")),{value:"PONG",bytes:7});
 assert.deepEqual(parseCIStagingRedisResponse(Buffer.from(":2\r\n")),{value:2,bytes:4});
 assert.deepEqual(parseCIStagingRedisResponse(Buffer.from("$3\r\nabc\r\n")),{value:"abc",bytes:9});
 assert.equal(parseCIStagingRedisResponse(Buffer.from("$3\r\nab")),undefined);
 assert.throws(()=>parseCIStagingRedisResponse(Buffer.from("-ERR denied\r\n")),/Redis error/);
 assert.throws(()=>parseCIStagingRedisResponse(Buffer.from("*1\r\n")),/denied/);
});

test("adapter accepts only exact loopback CI Redis and preserves EVAL boundaries",async()=>{
 const calls=[];
 const redis=createCIStagingRedis({url:"redis://127.0.0.1:6379/0",
  request:async(host,port,parts)=>{calls.push({host,port,parts});return parts[0]==="PING"?"PONG":1;}});
 assert.equal(await redis.ping(),"PONG");
 assert.equal(await redis.eval("return 1",{keys:["halo:key"],arguments:["1000"]}),1);
 assert.deepEqual(calls[1],{host:"127.0.0.1",port:6379,
  parts:["EVAL","return 1","1","halo:key","1000"]});
 for(const url of ["redis://localhost:6379/0","redis://127.0.0.1:6380/0",
  "redis://user@127.0.0.1:6379/0","redis://127.0.0.1:6379/1"])
  assert.throws(()=>createCIStagingRedis({url}),/denied/);
});
