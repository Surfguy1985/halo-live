// Pure reconciliation decision gate for uncertain outbound deliveries.
// This is NOT a sender, receipt verifier, or persistence implementation.
const id=x=>typeof x==="string"&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
export class ReconciliationError extends Error{constructor(code){super(code);this.name="ReconciliationError";this.code=code;}}
export function decideReconciliation({session,delivery,evidence,resolution,expectedRevision}={}){
 if(!session?.authenticated||!id(session.tenantID)||!id(session.actorID)||
  !Array.isArray(session.permissions)||!session.permissions.includes("deliveries:reconcile"))
  throw new ReconciliationError("FORBIDDEN");
 if(!delivery||![delivery.tenantID,delivery.consumerID,delivery.eventID].every(id)||
  session.tenantID!==delivery.tenantID)throw new ReconciliationError("FORBIDDEN_SCOPE");
 if(delivery.outcome!=="uncertain"||delivery.status!=="pending")
  throw new ReconciliationError("NOT_UNCERTAIN");
 if(!Number.isSafeInteger(delivery.reconciliationRevision)||delivery.reconciliationRevision<0||
  expectedRevision!==delivery.reconciliationRevision)
  throw new ReconciliationError("REVISION_CONFLICT");
 if(!["confirmed_delivered","confirmed_not_processed","escalate"].includes(resolution))
  throw new ReconciliationError("INVALID_RESOLUTION");
 if(resolution!=="escalate"){
  if(!evidence||evidence.serverVerified!==true||
   evidence.tenantID!==delivery.tenantID||evidence.consumerID!==delivery.consumerID||
   evidence.eventID!==delivery.eventID||!id(evidence.verificationID)||
   evidence.finding!==(resolution==="confirmed_delivered"?"processed":"not_processed"))
   throw new ReconciliationError("VERIFICATION_REQUIRED");
 }
 return Object.freeze({tenantID:delivery.tenantID,consumerID:delivery.consumerID,
  eventID:delivery.eventID,actorID:session.actorID,resolution,
  previousRevision:expectedRevision,nextRevision:expectedRevision+1,
  nextStatus:resolution==="confirmed_delivered"?"delivered":"pending",
  nextOutcome:resolution==="confirmed_delivered"?"acknowledged":"uncertain",
  // Explicit confirmation of non-processing does not send automatically.
  requiresOperatorRetryApproval:resolution==="confirmed_not_processed"});
}
