// Server-owned rotating RS256 keyset. Independent of the live HALO API.
// Fetcher MUST use a fixed, HTTPS identity-provider endpoint, with TLS validation.
// Never accept a JWKS URL or keys from user requests.
import { createPublicKey } from "node:crypto";
import { createRS256Verifier } from "./jwt-verifier.mjs";
const isObject=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);
export class RotatingJWTVerifier {
 constructor({issuer,audience,fetchJWKS,clock=()=>Date.now(),refreshMs=300000,maxKeys=16}={}) {
  if(typeof fetchJWKS!=="function"||!issuer||!audience||!Number.isSafeInteger(refreshMs)||refreshMs<1000)
   throw new TypeError("Trusted identity provider configuration required");
  this.issuer=issuer;this.audience=audience;this.fetchJWKS=fetchJWKS;
  this.clock=clock;this.refreshMs=refreshMs;this.maxKeys=maxKeys;
  this.keys=null;this.expiresAt=0;this.refreshing=null;
 }
 async refresh() {
  if(this.refreshing) return this.refreshing;
  this.refreshing=(async()=>{
   const jwks=await this.fetchJWKS();
   if(!isObject(jwks)||!Array.isArray(jwks.keys)||jwks.keys.length===0||jwks.keys.length>this.maxKeys)
    throw new Error("Invalid JWKS");
   const keys={};
   for(const key of jwks.keys) {
    if(!isObject(key)||key.kty!=="RSA"||key.use!=="sig"||key.alg!=="RS256"||
       typeof key.kid!=="string"||!key.kid||Object.hasOwn(keys,key.kid)) throw new Error("Invalid JWK");
    keys[key.kid]=createPublicKey({key,format:"jwk"}).export({type:"spki",format:"pem"});
   }
   const verifier=createRS256Verifier({issuer:this.issuer,audience:this.audience,publicKeys:keys,clock:this.clock});
   this.keys=verifier;
   this.expiresAt=this.clock()+this.refreshMs;
  })();
  try {await this.refreshing;} finally {this.refreshing=null;}
 }
 async verify(token) {
  if(this.clock()>=this.expiresAt||!this.keys) {
   try {await this.refresh();}catch{return null;} // fail closed
  }
  return this.keys(token);
 }
}
