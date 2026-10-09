import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {validateLayoutV1} from "./layout-contract.mjs";

const templates=JSON.parse(readFileSync(new URL("./fixtures/industry-workflows-v1.json",import.meta.url),"utf8"));
const clone=x=>structuredClone(x);
test("four industry templates are distinct, schema-valid and deterministic",()=>{
 assert.equal(templates.length,4);
 assert.deepEqual(templates.map(x=>x.industryID),["property_management","construction","transport","gig_marketplace"]);
 assert.equal(new Set(templates.map(x=>x.templateID)).size,4);
 for(const layout of templates){
  assert.equal(validateLayoutV1(layout),true,layout.industryID);
  assert.deepEqual(layout.blocks.map(x=>x.order),layout.blocks.map((_,i)=>i));
  assert.equal(new Set(layout.blocks.map(x=>x.id)).size,layout.blocks.length);
 }
});
test("block reorder is presentation-only and keeps stable block identities",()=>{
 for(const original of templates){
  const reordered=clone(original);
  reordered.blocks.reverse();
  reordered.blocks.forEach((b,i)=>{b.order=i;});
  assert.equal(validateLayoutV1(reordered),true,original.templateID);
  assert.deepEqual(new Set(reordered.blocks.map(x=>x.id)),new Set(original.blocks.map(x=>x.id)));
  assert.deepEqual(reordered.blocks.map(x=>x.id),original.blocks.map(x=>x.id).reverse());
 }
});
test("industry templates reject duplicate roles, invalid config and duplicate orders",()=>{
 for(const original of templates){
  const roles=clone(original);roles.blocks[0].visibleToRoles.push(roles.blocks[0].visibleToRoles[0]);
  assert.equal(validateLayoutV1(roles),false,original.templateID+" roles");
  const config=clone(original);config.blocks[0].config.__unexpected="unsafe";
  assert.equal(validateLayoutV1(config),false,original.templateID+" config");
  const order=clone(original);order.blocks[1].order=order.blocks[0].order;
  assert.equal(validateLayoutV1(order),false,original.templateID+" order");
 }
});
test("templates carry no execution authority, secrets or imperative commands",()=>{
 const serialized=JSON.stringify(templates);
 assert.doesNotMatch(serialized,/"(actorID|permissions|bearerToken|authorization|execute|script|apiKey)"\s*:/);
 for(const layout of templates){
  for(const b of layout.blocks){
   assert.ok(b.visibleToRoles.length>0);
   assert.ok(Object.values(b.config).every(v=>typeof v==="string"));
  }
 }
});
