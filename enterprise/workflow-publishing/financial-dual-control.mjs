// Pure financial retry dual-control policy. NEVER sends payments or invoices.
// The verifier and authorization sessions must originate from trusted services.
const ident=v=>typeof v==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(v);
export class FinancialControlError extends Error{constructor(code){super(code);this.name="FinancialControlError";this.code=code;}}
export function authorizeFinancialRetry({delivery,receipt,requester,approver,expectedRevision}={}){
 if(!delivery||![delivery.tenantID,delivery.consumerID,delivery.eventID].every(ident)||
  delivery.outcome!=="uncertain"||delivery.status!=="pending"||
  !Number.isSafeInteger(delivery.reconciliationRevision)||
  expectedRevision!==delivery.reconciliationRevision)
  throw new FinancialControlError("INVALID_OR_STALE_DELIVERY");
 const authorized=(actor,permission)=>actor?.authenticated===true&&
  actor.tenantID===delivery.tenantID&&ident(actor.actorID)&&
  Array.isArray(actor.permissions)&&actor.permissions.includes(permission);
 if(!authorized(requester,"financial_retry:request")||
  !authorized(approver,"financial_retry:approve"))
  throw new FinancialControlError("FORBIDDEN");
 if(requester.actorID===approver.actorID)
  throw new FinancialControlError("SEPARATION_OF_DUTIES");
 if(!receipt||receipt.serverVerified!==true||
  receipt.finding!=="not_processed"||
  receipt.tenantID!==delivery.tenantID||receipt.consumerID!==delivery.consumerID||
  receipt.eventID!==delivery.eventID||!ident(receipt.verificationID)||
  !ident(receipt.verifierID))
  throw new FinancialControlError("RECEIPT_NOT_VERIFIED");
 if(receipt.verifierID===requester.actorID||receipt.verifierID===approver.actorID)
  throw new FinancialControlError("INDEPENDENT_VERIFIER_REQUIRED");
 if(!Number.isSafeInteger(expectedRevision)||expectedRevision<0||
  expectedRevision===Number.MAX_SAFE_INTEGER)throw new FinancialControlError("INVALID_REVISION");
 return Object.freeze({tenantID:delivery.tenantID,consumerID:delivery.consumerID,
  eventID:delivery.eventID,previousRevision:expectedRevision,nextRevision:expectedRevision+1,
  requestedBy:requester.actorID,approvedBy:approver.actorID,
  verificationID:receipt.verificationID,decision:"eligible_for_controlled_retry",
  // No automatic queue release; approval must be committed and re-authorized
  // in an atomic DB transaction before issuing a fresh lease/permit.
  automaticallySend:false});
}
