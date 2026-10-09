// Reference publishing domain service. Not mounted on a live API.
// Store.transaction MUST provide a serializable/durable transaction in production.
import { createHash } from "node:crypto";
import {validateLayoutV1} from "./layout-contract.mjs";

export class PublishError extends Error {
  constructor(code, message) { super(message); this.name = "PublishError"; this.code = code; }
}

const text = x => typeof x === "string" && x.trim().length > 0;
const keys = obj => obj && typeof obj === "object" && !Array.isArray(obj);
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  keys(value) ? Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])])) : value;
export const layoutHash = value => createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");

export const validateLayout = validateLayoutV1;

export class WorkflowTemplatePublisher {
  constructor(store) { this.store = store; }
  async publish({session, templateID, idempotencyKey, proposal}) {
    // Session must originate in verified middleware, never request JSON.
    if (!session?.authenticated || !text(session.tenantID) || !text(session.actorID) ||
        !Array.isArray(session.permissions) || !session.permissions.includes("workflow:publish"))
      throw new PublishError("FORBIDDEN", "Not authorized");
    if (!text(templateID) || !text(idempotencyKey) || idempotencyKey.length > 128 ||
        !keys(proposal) || !Number.isSafeInteger(proposal.expectedRevision) ||
        proposal.expectedRevision < 0 || proposal.expectedRevision >= Number.MAX_SAFE_INTEGER ||
        !validateLayout(proposal.layout))
      throw new PublishError("INVALID", "Invalid publishing request");
    const layout = proposal.layout;
    if (layout.tenantID !== session.tenantID || layout.templateID !== templateID)
      throw new PublishError("FORBIDDEN", "Tenant or resource mismatch");
    if (!Array.isArray(session.industryIDs) || !session.industryIDs.includes(layout.industryID))
      throw new PublishError("FORBIDDEN", "Industry scope denied");
    const fingerprint = layoutHash({templateID, proposal});
    // Unique (tenant_id, idempotency_key), immutable revisions and audit event.
    return this.store.transaction(session.tenantID, templateID, async tx => {
      const previous = await tx.getIdempotency(idempotencyKey);
      if (previous) {
        if (previous.fingerprint !== fingerprint) throw new PublishError("IDEMPOTENCY_CONFLICT", "Key reused");
        return previous.response;
      }
      const current = await tx.getTemplate();
      const revision = current?.revision ?? 0;
      if (revision !== proposal.expectedRevision)
        throw new PublishError("REVISION_CONFLICT", "Template changed");
      if (current && current.industryID !== layout.industryID)
        throw new PublishError("FORBIDDEN", "Industry cannot change");
      const result = Object.freeze({ templateID, revision: revision + 1, templateVersion: layout.templateVersion });
      await tx.saveTemplate({ ...layout, revision: result.revision });
      await tx.saveIdempotency(idempotencyKey, {fingerprint, response: result});
      await tx.appendAudit({ event: "workflow.template.published", tenantID: session.tenantID,
        actorID: session.actorID, templateID, revision: result.revision,
        contentHash: layoutHash(layout), idempotencyKey });
      return result;
    }, layout.industryID, session.actorID);
  }
}
