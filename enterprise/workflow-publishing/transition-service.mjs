// Isolated transactional orchestration contract. Not mounted to an API.
// Production adapter MUST lock the tenant-scoped work item, run serializable
// transactions, and commit state, idempotency, audit and outbox atomically.
import {createHash} from "node:crypto";
import {decideWorkflowTransition} from "./transition-decision.mjs";

const id=x=>typeof x==="string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(x);
const stable=x=>Array.isArray(x)?x.map(stable):x && typeof x==="object"?
  Object.fromEntries(Object.entries(x).sort(([a],[b])=>a.localeCompare(b)).map(([k,v])=>[k,stable(v)])):x;
const hash=x=>createHash("sha256").update(JSON.stringify(stable(x))).digest("hex");
export class TransitionError extends Error {
  constructor(code){super(code);this.name="TransitionError";this.code=code;}
}

export class WorkflowTransitionService {
  constructor(store){if(!store || typeof store.transaction!=="function")throw TypeError("transactional store required");this.store=store;}
  async execute({session,workItemID,action,expectedRevision,idempotencyKey,evidence}={}) {
    if(!session?.authenticated || !id(session.tenantID) || !id(session.actorID) ||
      !id(workItemID) || !id(idempotencyKey) || !id(action) ||
      !Number.isSafeInteger(expectedRevision) || expectedRevision<0)
      throw new TransitionError("INVALID_REQUEST");
    // Evidence is trusted ONLY when produced by a separately authenticated
    // server verifier. This adapter has no client-facing request parser.
    const requestFingerprint=hash({workItemID,action,expectedRevision,evidence:evidence??null});
    return this.store.transaction(session.tenantID,workItemID,async tx=>{
      const previous=await tx.getIdempotency(idempotencyKey);
      if(previous){
        if(previous.fingerprint!==requestFingerprint)throw new TransitionError("IDEMPOTENCY_CONFLICT");
        return previous.response;
      }
      const workItem=await tx.getLockedWorkItem();
      if(!workItem)throw new TransitionError("NOT_FOUND");
      const decision=decideWorkflowTransition({session,workItem,action,expectedRevision,evidence});
      if(!decision.allowed)throw new TransitionError(decision.code);
      const proposed=decision.transition;
      // A production transaction adapter MUST do CAS against the locked row,
      // and MUST fail if the row count is not exactly one.
      await tx.updateState({
        expectedRevision:proposed.previousRevision,
        revision:proposed.nextRevision,state:proposed.to
      });
      const result=Object.freeze({
        workItemID,tenantID:session.tenantID,
        state:proposed.to,revision:proposed.nextRevision
      });
      await tx.appendAudit({
        type:"workflow.work_item.transitioned",tenantID:session.tenantID,
        workItemID,actorID:session.actorID,action,
        from:proposed.from,to:proposed.to,revision:proposed.nextRevision,
        idempotencyKey
      });
      // Event is a stored intent only. Consumers require their own dedupe.
      await tx.appendOutbox({
        eventID:hash({tenantID:session.tenantID,workItemID,idempotencyKey}),
        type:"workflow.work_item.transitioned",tenantID:session.tenantID,
        workItemID,revision:proposed.nextRevision,action
      });
      await tx.saveIdempotency(idempotencyKey,{fingerprint:requestFingerprint,response:result});
      return result;
    });
  }
}
