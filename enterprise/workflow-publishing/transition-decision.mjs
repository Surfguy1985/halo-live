// Pure transition decision kernel. NEVER directly performs side effects.
// Server must authenticate identity, load locked authoritative state and commit
// revisions/audit/outbox atomically before invoking downstream integrations.
const id = value => typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value);
const object = x => x !== null && typeof x === "object" && !Array.isArray(x);
const uniqueIDs = values => Array.isArray(values) && values.length > 0 && values.length <= 32 &&
  values.every(id) && new Set(values).size === values.length;
const fail = code => Object.freeze({allowed:false,code});
const states = new Set(["created","assigned","accepted","in_progress","evidence_pending","review_pending","approved","closed","cancelled"]);
const rules = Object.freeze({
  assign: {from:"created",to:"assigned",roles:["dispatcher","manager"]},
  accept: {from:"assigned",to:"accepted",roles:["assignee"]},
  start: {from:"accepted",to:"in_progress",roles:["assignee"]},
  submit_evidence: {from:"in_progress",to:"evidence_pending",roles:["assignee"],evidence:true},
  request_review: {from:"evidence_pending",to:"review_pending",roles:["manager","dispatcher"]},
  approve: {from:"review_pending",to:"approved",roles:["approver"],evidence:true},
  close: {from:"approved",to:"closed",roles:["manager"],evidence:true}
});
const transitions = new Set(Object.keys(rules));
export const WORKFLOW_STATES = Object.freeze([...states]);
export const WORKFLOW_ACTIONS = Object.freeze([...transitions]);

export function decideWorkflowTransition({session,workItem,action,expectedRevision,evidence}={}) {
  if (!object(session) || !session.authenticated || !id(session.tenantID) ||
    !id(session.actorID) || !uniqueIDs(session.roles) ||
    !Array.isArray(session.industryIDs) || !session.industryIDs.every(id))
    return fail("UNAUTHORIZED");
  if (!object(workItem) || !id(workItem.id) || !id(workItem.tenantID) ||
    !id(workItem.industryID) || !id(workItem.templateID) ||
    !Number.isSafeInteger(workItem.templateVersion) || workItem.templateVersion < 1 ||
    !states.has(workItem.state) || !Number.isSafeInteger(workItem.revision) || workItem.revision < 0)
    return fail("INVALID_WORK_ITEM");
  if (workItem.tenantID !== session.tenantID ||
    !session.industryIDs.includes(workItem.industryID))
    return fail("FORBIDDEN_SCOPE");
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0)
    return fail("INVALID_REVISION");
  if (expectedRevision !== workItem.revision) return fail("REVISION_CONFLICT");
  if (!transitions.has(action)) return fail("INVALID_ACTION");
  const rule = rules[action];
  if (workItem.state !== rule.from) return fail("INVALID_TRANSITION");
  if (!session.roles.some(role => rule.roles.includes(role))) return fail("FORBIDDEN_ROLE");
  if (action === "accept" || action === "start" || action === "submit_evidence") {
    if (!id(workItem.assigneeID) || workItem.assigneeID !== session.actorID)
      return fail("FORBIDDEN_ASSIGNEE");
  }
  if (action === "approve" && workItem.assigneeID === session.actorID)
    return fail("SEPARATION_OF_DUTIES");
  if (rule.evidence) {
    // Only a trusted server-side verifier may set this flag. The state engine
    // does NOT inspect client evidence URLs or treat images as verified.
    if (!object(evidence) || evidence.serverVerified !== true ||
      evidence.tenantID !== workItem.tenantID || evidence.workItemID !== workItem.id ||
      !id(evidence.verificationID))
      return fail("EVIDENCE_REQUIRED");
  }
  if (workItem.revision === Number.MAX_SAFE_INTEGER) return fail("REVISION_EXHAUSTED");
  return Object.freeze({allowed:true,transition:Object.freeze({
    workItemID:workItem.id,tenantID:workItem.tenantID,industryID:workItem.industryID,
    templateID:workItem.templateID,templateVersion:workItem.templateVersion,
    actorID:session.actorID,action,from:workItem.state,to:rule.to,
    previousRevision:workItem.revision,nextRevision:workItem.revision+1
  })});
}
