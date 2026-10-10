// Reference publishing domain service. Not mounted on a live API.
// Store.transaction MUST provide a serializable/durable transaction in production.
import { createHash, timingSafeEqual } from "node:crypto";
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

  async reconcile({session, templateID, idempotencyKey, proposal}) {
    // Reconciliation uses the caller's current, server-verified membership.
    // It only reads the receipt written by the original publish transaction;
    // it must never call publish() or reconstruct/replay the proposal.
    if (!session?.authenticated || !text(session.tenantID) || !text(session.actorID) ||
        !Array.isArray(session.permissions) || !session.permissions.includes("workflow:publish"))
      throw new PublishError("FORBIDDEN", "Not authorized");
    if (!text(templateID) || templateID.length > 128 ||
        !text(idempotencyKey) || idempotencyKey.length > 128 ||
        !keys(proposal) || !Number.isSafeInteger(proposal.expectedRevision) ||
        proposal.expectedRevision < 0 || proposal.expectedRevision >= Number.MAX_SAFE_INTEGER ||
        !validateLayout(proposal.layout))
      throw new PublishError("INVALID", "Invalid reconciliation request");
    const layout = proposal.layout;
    if (layout.tenantID !== session.tenantID || layout.templateID !== templateID)
      throw new PublishError("FORBIDDEN", "Tenant or resource mismatch");
    if (!Array.isArray(session.industryIDs) || session.industryIDs.length === 0 ||
        session.industryIDs.length > 128 ||
        session.industryIDs.some(industryID => !text(industryID) || industryID.length > 128))
      throw new PublishError("FORBIDDEN", "Industry scope denied");
    if (!session.industryIDs.includes(layout.industryID))
      throw new PublishError("FORBIDDEN", "Industry scope denied");
    if (typeof this.store?.findPublishReceipt !== "function")
      throw new Error("Workflow receipt lookup unavailable");

    const receipt = await this.store.findPublishReceipt(
      session.tenantID, templateID, idempotencyKey, [layout.industryID]
    );
    if (receipt === null)
      throw new PublishError("PUBLISH_REQUEST_NOT_FOUND", "Publish request not found");
    const fingerprint = layoutHash({templateID, proposal});
    if (typeof receipt.fingerprint !== "string" || !/^[0-9a-f]{64}$/.test(receipt.fingerprint))
      throw new Error("Invalid stored workflow publish fingerprint");
    if (!timingSafeEqual(Buffer.from(receipt.fingerprint,"hex"),Buffer.from(fingerprint,"hex")))
      throw new PublishError("IDEMPOTENCY_CONFLICT", "Request does not match stored receipt");
    const response = receipt.response;
    // Treat malformed database data as an internal failure instead of returning
    // an ambiguous or cross-resource receipt to the caller.
    if (!keys(response) || Object.keys(response).sort().join(",") !== "revision,templateID,templateVersion" ||
        response.templateID !== templateID ||
        !Number.isSafeInteger(response.revision) ||
        response.revision !== proposal.expectedRevision + 1 ||
        !Number.isSafeInteger(response.templateVersion) ||
        response.templateVersion !== layout.templateVersion)
      throw new Error("Invalid stored workflow publish receipt");
    return Object.freeze({
      requestID:idempotencyKey,
      outcome:"COMMITTED",
      result:Object.freeze({...response})
    });
  }
}
