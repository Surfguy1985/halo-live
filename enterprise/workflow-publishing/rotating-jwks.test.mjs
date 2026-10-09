import test from "node:test";
import assert from "node:assert/strict";
import {generateKeyPairSync,sign} from "node:crypto";
import {RotatingJWTVerifier} from "./rotating-jwks.mjs";
const pair=()=>generateKeyPairSync("rsa",{modulusLength:2048});
const first=pair(),second=pair();
const jwk=(key,kid)=>({...key.export({format:"jwk"}),kid,kty:"RSA",use:"sig",alg:"RS256"});
const now=1_700_000_000;
const signToken=(key,kid)=>{
 const enc=value=>Buffer.from(JSON.stringify(value)).toString("base64url");
 const data=enc({typ:"JWT",alg:"RS256",kid})+"."+enc({iss:"https://identity.example",aud:"halo",sub:"actor",
  iat:now-100,exp:now+500});
 return data+"."+sign("RSA-SHA256",Buffer.from(data),key).toString("base64url");
};
test("rotates accepted keys after refresh window",async()=>{
 let clock=now*1000,active=first,loads=0;
 const verifier=new RotatingJWTVerifier({issuer:"https://identity.example",audience:"halo",
  clock:()=>clock,refreshMs:1000,fetchJWKS:async()=>{loads++;return {keys:[jwk(active.publicKey,active===first?"old":"new")]};}});
 assert.deepEqual(await verifier.verify(signToken(first.privateKey,"old")),{subject:"actor"});
 active=second;clock+=1500;
 assert.equal(await verifier.verify(signToken(first.privateKey,"old")),null);
 assert.deepEqual(await verifier.verify(signToken(second.privateKey,"new")),{subject:"actor"});
 assert.equal(loads,2);
});
test("fails closed on refresh outage instead of using expired cached keys",async()=>{
 let clock=now*1000,fail=false;
 const verifier=new RotatingJWTVerifier({issuer:"https://identity.example",audience:"halo",clock:()=>clock,
  refreshMs:1000,fetchJWKS:async()=>{if(fail)throw Error("network");return {keys:[jwk(first.publicKey,"old")]};}});
 assert.ok(await verifier.verify(signToken(first.privateKey,"old")));
 fail=true;clock+=1500;
 assert.equal(await verifier.verify(signToken(first.privateKey,"old")),null);
});
