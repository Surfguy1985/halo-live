import test from "node:test";
import assert from "node:assert/strict";
import {generateKeyPairSync,sign} from "node:crypto";
import {createRS256Verifier} from "./jwt-verifier.mjs";
const {publicKey,privateKey}=generateKeyPairSync("rsa",{modulusLength:2048});
const pem=publicKey.export({type:"spki",format:"pem"});
const now=1_700_000_000;
const verifier=createRS256Verifier({issuer:"https://id.example.test",audience:"halo-api",
 publicKeys:{key1:pem},clock:()=>now*1000});
const encode=value=>Buffer.from(JSON.stringify(value)).toString("base64url");
function make(claims={},header={}) {
 const h=encode({alg:"RS256",typ:"JWT",kid:"key1",...header});
 const p=encode({iss:"https://id.example.test",aud:"halo-api",sub:"user-1",
  iat:now-60,exp:now+600,...claims});
 const signed=h+"."+p;
 return signed+"."+sign("RSA-SHA256",Buffer.from(signed),privateKey).toString("base64url");
}
test("valid signature and claims yield subject",async()=>assert.deepEqual(await verifier(make()),{subject:"user-1"}));
test("rejects expired, wrong issuer, wrong audience and future issued",async()=>{
 for(const claim of [{exp:now-1},{iss:"fake"},{aud:"elsewhere"},{iat:now+100}])
  assert.equal(await verifier(make(claim)),null);
});
test("rejects unknown kid, algorithm swap, and tampered payload",async()=>{
 assert.equal(await verifier(make({}, {kid:"unknown"})),null);
 assert.equal(await verifier(make({}, {alg:"HS256"})),null);
 const token=make(),parts=token.split(".");
 parts[1]=encode({iss:"https://id.example.test",aud:"halo-api",sub:"other",iat:now-60,exp:now+600});
 assert.equal(await verifier(parts.join(".")),null);
});
