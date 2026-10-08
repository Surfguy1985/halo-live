// Reference publishing domain service. Not mounted on a live API.
// Store.transaction MUST provide a serializable/durable transaction in production.
import { createHash } from "node:crypto";

export class PublishError extends Error {
  constructor(code, message) { super(message); this.name = "PublishError"; this.code = code; }
}

const kinds = new Set(["assignment","location","checklist","photoProof","pricing","approval","messaging","closeout"]);
const text = x => typeof x === "string" && x.trim().length > 0;
const keys = obj => obj && typeof obj === "object" && !Array.isArray(obj);
const canonical = value => Array.isArray(value) ? value.map(canonical) :
  keys(value) ? Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])])) : value;
const hash = value => createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");

export function validateLayout(layout) {
  if (!keys(layout) || layout.schemaVersion !== 1 || !text(layout.templateID) ||
      !Number.isSafeInteger(layout.templateVersion) || layout.templateVersion < 1 ||
      !text(layout.tenantID) || !text(layout.industryID) ||
      !Array.isArray(layout.blocks) || layout.blocks.length > 100) return false;
  const ids = new Set(), orders = new Set();
  return layout.blocks.every(b => {
    if (!keys(b) || !text(b.id) || !text(b.title) || !kinds.has(b.kind) ||
        !Number.isSafeInteger(b.order) || b.order < 0 ||
        typeof b.required !== "boolean" || !Array.isArray(b.visibleToRoles) ||
        b.visibleToRoles.length === 0 || !b.visibleToRoles.every(text) ||
        !keys(b.config) || !Object.entries(b.config).every(([k,v]) => text(k) && typeof v === "string") ||
        ids.has(b.id) || orders.has(b.order)) return false;
    ids.add(b.id); orders.add(b.order); return true;
  });
}

export class WorkflowTemplatePublisher {
  constructor(store) { this.store = store; }
  async publish({session, templateID, idempotencyKey, proposal}) {
    // Session must originate in verified middleware, never request JSON.
    if (!session?.authenticated || !text(session.tenantID) || !text(session.actorID) ||
        !Array.isArray(session.permissions) || !session.permissions.includes("workflow:publish"))
      throw new PublishError("FORBIDDEN", "Not authorized");
    if (!text(templateID) || !text(idempotencyKey) || idempotencyKey.length > 128 ||
        !keys(proposal) || !Number.isSafeInteger(proposal.expectedRevision) ||
        proposal.expectedRevision < 0 || !validateLayout(proposal.layout))
      throw new PublishError("INVALID", "Invalid publishing request");
    const layout = proposal.layout;
    if (layout.tenantID !== session.tenantID || layout.templateID !== templateID)
      throw new PublishError("FORBIDDEN", "Tenant or resource mismatch");
    if (!Array.isArray(session.industryIDs) || !session.industryIDs.includes(layout.industryID))
      throw new PublishError("FORBIDDEN", "Industry scope denied");
    const fingerprint = hash({templateID, proposal});
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
      await tx.appendAudit({ event: "workflow.template.published", tenantID: session.tenantID,
        actorID: session.actorID, templateID, revision: result.revision,
        contentHash: hash(layout), idempotencyKey });
      await tx.saveIdempotency(idempotencyKey, {fingerprint, response: result});
      return result;
    });
  }
}
