import test from "node:test";
import assert from "node:assert/strict";
import {DispatchPermitGateway,PermitError} from "./dispatch-permit-gateway.mjs";
const request={tenantID:"tenant-a",consumerID:"enforcer",eventID:"a".repeat(64),permitID:"permit-a",registrationRevision:4,now:2000};
function fixture({enabled=true,revision=4,expiresAt=3000,invalidated=false}={}){
 let consumed=false;
 const store={consumeIfAuthorized:async ({registrationRevision,now})=>{
  if(consumed||invalidated||!enabled||revision!==registrationRevision||now>=expiresAt)return false;
  consumed=true;return true;
 }};
 return new DispatchPermitGateway(store);
}
test("valid permit consumed once and replay denied",async()=>{
 const gateway=fixture();
 assert.equal((await gateway.authorizeSend(request)).authorized,true);
 await assert.rejects(()=>gateway.authorizeSend(request),e=>e.code==="PERMIT_EXPIRED_REVOKED_OR_REPLAYED");
});
test("expired, revoked or stale registration denies send",async()=>{
 for(const config of [{expiresAt:2000},{enabled:false},{revision:5},{invalidated:true}]){
  await assert.rejects(()=>fixture(config).authorizeSend(request),PermitError);
 }
});
test("untrusted malformed requests rejected before store call",async()=>{
 let calls=0;const gateway=new DispatchPermitGateway({consumeIfAuthorized:async()=>{calls++;return true;}});
 await assert.rejects(()=>gateway.authorizeSend({...request,tenantID:"../tenant"}),PermitError);
 assert.equal(calls,0);
});
