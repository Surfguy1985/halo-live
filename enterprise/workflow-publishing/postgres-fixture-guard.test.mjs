import test from "node:test";
import assert from "node:assert/strict";
import {readFile,readdir} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import {join} from "node:path";

// Fast static guard, also runs when the PostgreSQL service is queued.
test("Postgres integration fixtures use a valid role-existence SELECT",async()=>{
 const dir=fileURLToPath(new URL(".",import.meta.url));
 const entries=(await readdir(dir)).filter(name=>name.endsWith(".integration.test.mjs"));
 for(const name of entries){
  const body=await readFile(join(dir,name),"utf8");
  assert.doesNotMatch(body,/SELECT\\s+FROM\\s+pg_roles/i, name+" has missing projection");
 }
});
