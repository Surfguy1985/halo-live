// Dispatch authorization gate. Must run immediately before each attempted send.
// Trusted registry reader is server-owned. No network delivery is implemented.
const valid=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export async function authorizeDeliveryNow({delivery,registry}={}){
 if(!registry||typeof registry.lookup!=="function")throw TypeError("trusted registry required");
 if(!delivery||![delivery.tenantID,delivery.consumerID,delivery.eventID].every(valid)||
  typeof delivery.action!=="string"||delivery.action.length>64||
  typeof delivery.type!=="string"||delivery.type.length>128)
  return Object.freeze({authorized:false,reason:"INVALID_DELIVERY"});
 const record=await registry.lookup(delivery.tenantID,delivery.consumerID);
 if(!record||record.tenantID!==delivery.tenantID||
    record.consumerID!==delivery.consumerID||record.enabled!==true||
    !Number.isSafeInteger(record.revision)||record.revision<1)
  return Object.freeze({authorized:false,reason:"REVOKED_OR_MISSING"});
 if(!Array.isArray(record.eventTypes)||!record.eventTypes.includes(delivery.type)||
    !Array.isArray(record.allowedActions)||!record.allowedActions.includes(delivery.action))
  return Object.freeze({authorized:false,reason:"SUBSCRIPTION_DENIED"});
 return Object.freeze({authorized:true,registrationRevision:record.revision});
}
