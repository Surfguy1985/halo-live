// HALO workflow layout v1: server-owned, industry-neutral data contract.
// This validates template *presentation*. It grants no execution authority.
const kinds = Object.freeze({
  assignment: {allowSelfAssign: "boolean"},
  location: {radiusMeters: [1, 50_000]},
  checklist: {minChecks: [0, 100]},
  photoProof: {minPhotos: [1, 20]},
  pricing: {currencyCode: "currency", requireApprovedQuote: "boolean"},
  approval: {minApprovers: [1, 10]},
  messaging: {channel: "channel"},
  closeout: {requireVerifiedEvidence: "boolean"}
});
const identifier = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
const exactKeys = (value, allowed) => Object.keys(value).every(key => allowed.includes(key));
const validID = value => typeof value === "string" && identifier.test(value);
const validTitle = value => typeof value === "string" && value.trim().length > 0 && value.length <= 160;
const validConfig = (kind, config) => {
  if (!object(config) || Object.keys(config).length > 8) return false;
  const spec = kinds[kind];
  if (!spec) return false;
  return Object.entries(config).every(([name, value]) => {
    if (!Object.hasOwn(spec, name) || typeof value !== "string" || value.length > 128) return false;
    const type = spec[name];
    if (type === "boolean") return value === "true" || value === "false";
    if (type === "currency") return /^[A-Z]{3}$/.test(value);
    if (type === "channel") return /^[a-z][a-z0-9_-]{0,63}$/.test(value);
    if (Array.isArray(type)) return /^(0|[1-9][0-9]*)$/.test(value) && Number.isSafeInteger(Number(value)) && Number(value) >= type[0] && Number(value) <= type[1];
    return false;
  });
};

export const WORKFLOW_LAYOUT_SCHEMA_VERSION = 1;
export const WORKFLOW_BLOCK_KINDS = Object.freeze(Object.keys(kinds));

export function validateLayoutV1(layout) {
  if (!object(layout) || !exactKeys(layout,
    ["schemaVersion", "tenantID", "industryID", "templateID", "templateVersion", "blocks"]) ||
    layout.schemaVersion !== WORKFLOW_LAYOUT_SCHEMA_VERSION ||
    !validID(layout.tenantID) || !validID(layout.industryID) || !validID(layout.templateID) ||
    !Number.isSafeInteger(layout.templateVersion) || layout.templateVersion < 1 ||
    !Array.isArray(layout.blocks) || layout.blocks.length > 100) return false;

  const ids = new Set();
  const orders = new Set();
  return layout.blocks.every(block => {
    if (!object(block) || !exactKeys(block,
      ["id", "kind", "title", "order", "required", "visibleToRoles", "config"]) ||
      !validID(block.id) || !validTitle(block.title) || !Object.hasOwn(kinds, block.kind) ||
      !Number.isSafeInteger(block.order) || block.order < 0 ||
      typeof block.required !== "boolean" ||
      !Array.isArray(block.visibleToRoles) || block.visibleToRoles.length < 1 || block.visibleToRoles.length > 16 ||
      !block.visibleToRoles.every(validID) ||
      new Set(block.visibleToRoles).size !== block.visibleToRoles.length ||
      !validConfig(block.kind, block.config) || ids.has(block.id) || orders.has(block.order)) return false;
    ids.add(block.id);
    orders.add(block.order);
    return true;
  });
}
