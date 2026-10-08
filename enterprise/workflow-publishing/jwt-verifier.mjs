// Server-only RS256 JWT verification via Node WebCrypto. Isolated reference adapter.
// Production requires controlled JWKS rotation, revocation strategy and telemetry.
// Do not allow client-supplied issuer, audience, keys or algorithm.
import { createPublicKey, verify as cryptoVerify } from "node:crypto";
const decode = part => {
 if (!/^[A-Za-z0-9_-]+$/.test(part)) throw Error("Invalid token encoding");
 return Buffer.from(part.replace(/-/g,"+").replace(/_/g,"/"),"base64");
};
const json = part => JSON.parse(decode(part).toString("utf8"));
const plain = value => value!==null && typeof value==="object" && !Array.isArray(value);
const fixedString = value => typeof value==="string" && value.length>0;
export function createRS256Verifier({issuer,audience,publicKeys,clock=()=>Date.now(),maxAgeSeconds=3600}={}) {
 if(!fixedString(issuer)||!fixedString(audience)||!plain(publicKeys)||
 !Number.isSafeInteger(maxAgeSeconds)||maxAgeSeconds<=0) throw TypeError("Trusted issuer, audience and key map required");
 const keys=new Map();
 for(const [kid,pem] of Object.entries(publicKeys)) {
  if(!fixedString(kid)||!fixedString(pem)) throw TypeError("Invalid key");
  const key=createPublicKey(pem);
  if(key.asymmetricKeyType!=="rsa") throw TypeError("RSA public key required");
  keys.set(kid,key);
 }
 if(keys.size===0) throw TypeError("At least one key required");
 return async token=>{
  try {
   if(typeof token!=="string"||token.length>8192) return null;
   const parts=token.split(".");
   if(parts.length!==3) return null;
   const [headerPart,payloadPart,signaturePart]=parts;
   const header=json(headerPart),claims=json(payloadPart);
   if(!plain(header)||header.alg!=="RS256"||header.typ!=="JWT"||
      !fixedString(header.kid)||!keys.has(header.kid)||!plain(claims)) return null;
   const now=Math.floor(clock()/1000);
   if(claims.iss!==issuer || !(claims.aud===audience ||
     (Array.isArray(claims.aud)&&claims.aud.includes(audience))) ||
     !fixedString(claims.sub) || typeof claims.exp!=="number" ||
     typeof claims.iat!=="number" || !Number.isSafeInteger(claims.exp) ||
     !Number.isSafeInteger(claims.iat) || claims.exp<=now || claims.iat>now+30 ||
     claims.exp-claims.iat>maxAgeSeconds || claims.exp<=claims.iat ||
     (claims.nbf!==undefined && (!Number.isSafeInteger(claims.nbf)||claims.nbf>now))) return null;
   const signature=decode(signaturePart);
   const valid=cryptoVerify("RSA-SHA256",Buffer.from(headerPart+"."+payloadPart),
    keys.get(header.kid),signature);
   return valid?{subject:claims.sub}:null;
  }catch{return null;}
 };
}
