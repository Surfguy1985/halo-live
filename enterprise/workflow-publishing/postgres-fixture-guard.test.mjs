import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {join} from "node:path";

// Match the actual whitespace between SELECT and FROM, not a literal \\s.
const malformedRoleQuery = /SELECT\s+FROM\s+pg_roles/i;
test("guard recognizes a known-invalid PostgreSQL role query",()=>{
 assert.match("IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='executor')",malformedRoleQuery);
 assert.doesNotMatch("IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='executor')",malformedRoleQuery);
});
test("all PostgreSQL integration fixtures avoid missing SELECT projection",async()=>{
 const dir=fileURLToPath(new URL(".",import.meta.url));
 const entries=(await readdir(dir)).filter(name=>name.endsWith(".integration.test.mjs"));
 for(const name of entries){
  const body=await readFile(join(dir,name),"utf8");
  assert.doesNotMatch(body,malformedRoleQuery,name+" has missing projection");
 }
});
