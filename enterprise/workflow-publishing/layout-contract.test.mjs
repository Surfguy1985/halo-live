import test from "node:test";
import assert from "node:assert/strict";
import {validateLayoutV1, WORKFLOW_BLOCK_KINDS} from "./layout-contract.mjs";

const layout = (industryID="construction") => ({
  schemaVersion:1, tenantID:"tenant-one", industryID, templateID:"dispatch", templateVersion:1,
  blocks:[{id:"assignment", kind:"assignment", title:"Assign the job", order:0,
    required:true, visibleToRoles:["manager","crew"], config:{allowSelfAssign:"false"}}]
});
const clone = value => JSON.parse(JSON.stringify(value));

test("accepts legitimate multi-industry templates and Swift photoProof configuration",()=>{
  for (const industry of ["construction","property_management","transport","gig_marketplace"])
    assert.equal(validateLayoutV1(layout(industry)),true,industry);
  const example = layout();
  example.blocks.push({id:"photos",kind:"photoProof",title:"Proof of work",order:1,
    required:true,visibleToRoles:["crew"],config:{minPhotos:"1"}});
  assert.equal(validateLayoutV1(example),true);
  assert.equal(WORKFLOW_BLOCK_KINDS.length,8);
});

test("all block kinds recognize only their bounded typed configuration",()=>{
  const configs = {
    assignment:{allowSelfAssign:"true"},location:{radiusMeters:"150"},checklist:{minChecks:"0"},
    photoProof:{minPhotos:"3"},pricing:{currencyCode:"USD",requireApprovedQuote:"true"},
    approval:{minApprovers:"2"},messaging:{channel:"crew_updates"},closeout:{requireVerifiedEvidence:"false"}
  };
  for(const kind of WORKFLOW_BLOCK_KINDS){
    const example=layout();example.blocks[0].kind=kind;example.blocks[0].config=configs[kind];
    assert.equal(validateLayoutV1(example),true,kind);
  }
});

test("rejects unexpected layout and block properties, including prototype-shaped config keys",()=>{
  const extra = layout();extra.executionScript="malicious";
  assert.equal(validateLayoutV1(extra),false);
  const block = layout();block.blocks[0].command="rm -rf /";
  assert.equal(validateLayoutV1(block),false);
  const config=layout();config.blocks[0].config=JSON.parse('{"__proto__":"true"}');
  assert.equal(validateLayoutV1(config),false);
  const polluted=layout();polluted.blocks[0].kind="__proto__";
  assert.equal(validateLayoutV1(polluted),false);
});

test("rejects unbounded IDs, titles, roles, configs, and malformed numeric values",()=>{
  for (const value of ["", " ", "a".repeat(129), "bad/id", "abc.def"]){
    const data=layout();data.blocks[0].id=value;assert.equal(validateLayoutV1(data),false,value);
  }
  const huge=layout();huge.blocks[0].title="A".repeat(161);
  assert.equal(validateLayoutV1(huge),false);
  for (const roles of [[],["manager","manager"],Array.from({length:17},(_,i)=>"role-"+i)]){
    const data=layout();data.blocks[0].visibleToRoles=roles;
    assert.equal(validateLayoutV1(data),false);
  }
  for (const bad of ["-1","1.1","01","1e3","Infinity","21","99999999999999999999999"]){
    const data=layout();data.blocks[0].kind="photoProof";data.blocks[0].config={minPhotos:bad};
    assert.equal(validateLayoutV1(data),false,bad);
  }
  const badCurrency=layout();badCurrency.blocks[0].kind="pricing";badCurrency.blocks[0].config={currencyCode:"usd"};
  assert.equal(validateLayoutV1(badCurrency),false);
});

test("rejects duplicate IDs, duplicate order and unexpected configuration on another block kind",()=>{
  const dup = layout();dup.blocks.push({...clone(dup.blocks[0]),order:1});
  assert.equal(validateLayoutV1(dup),false);
  const duplicateOrder=layout();duplicateOrder.blocks.push({...clone(dup.blocks[0]),id:"two"});
  assert.equal(validateLayoutV1(duplicateOrder),false);
  const mismatch=layout();mismatch.blocks[0].kind="messaging";
  assert.equal(validateLayoutV1(mismatch),false);
});
