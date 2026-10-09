import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {WORKFLOW_BLOCK_KINDS, WORKFLOW_LAYOUT_SCHEMA_VERSION, validateLayoutV1} from "./layout-contract.mjs";

const swift = path => readFileSync(fileURLToPath(new URL("../../NativeiOS/HaloField/"+path, import.meta.url)), "utf8");

test("Swift workflow layout schema version and block kinds match backend", () => {
 const source=swift("Domain/HaloWorkflowBlocks.swift");
 const version=source.match(/static let supportedSchemaVersion\s*=\s*(\d+)/);
 assert.ok(version, "Swift layout schema version not found");
 assert.equal(Number(version[1]), WORKFLOW_LAYOUT_SCHEMA_VERSION);
 const enumBody=source.match(/enum Kind:\s*String, Codable, CaseIterable\s*\{([\s\S]*?)\}/);
 assert.ok(enumBody, "Swift block kinds not found");
 const kinds=[...enumBody[1].matchAll(/\bcase\s+([^\n]+)/g)].flatMap(m=>m[1].split(",").map(x=>x.trim()));
 assert.deepEqual(kinds.sort(), [...WORKFLOW_BLOCK_KINDS].sort());
});

test("Swift Codable layout field names match backend validation contract", () => {
 const source=swift("Domain/HaloWorkflowBlocks.swift");
 for (const key of ["schemaVersion","templateID","templateVersion","tenantID","industryID","blocks",
  "id","kind","title","order","required","visibleToRoles","config"]) {
  assert.match(source,new RegExp("\\blet "+key+"\\s*:"), "Swift field missing: "+key);
 }
 assert.equal(validateLayoutV1({
  schemaVersion:1,templateID:"turn-v1",templateVersion:1,tenantID:"tenant-a",industryID:"property",blocks:[
   {id:"proof",kind:"photoProof",title:"Photos",order:0,required:true,visibleToRoles:["crew"],config:{minPhotos:"2"}}
  ]
 }),true);
});

test("Swift publish proposal and backend HTTP endpoint preserve revision and idempotency fields", () => {
 const source=swift("Domain/HaloTemplatePublishing.swift");
 for (const key of ["requestID","expectedRevision","layout"]) assert.match(source,new RegExp("\\blet "+key+"\\s*:"));
 assert.match(source,/POST \/v1\/workflow-templates\/\{templateID\}\/publish/);
 const handler=readFileSync(fileURLToPath(new URL("./api-handler.mjs",import.meta.url)),"utf8");
 assert.match(handler,/parsed\.requestID!==key/);
 assert.match(handler,/parsed\.expectedRevision/);
 assert.match(handler,/idempotencyKey:key/);
});

test("native mobile transport is not silently treated as the enterprise workflow API", () => {
 const source=swift("Networking/HaloAPI.swift");
 assert.match(source,/halo-back-office-copy-1d779ace\.base44\.app/);
 assert.match(source,/\/functions\/nativeFieldMobile/);
 assert.doesNotMatch(source,/\/v1\/workflow-templates\//,
  "Workflow publishing added to HaloAPI: review auth, tenant, version and retry contract before shipping");
});
