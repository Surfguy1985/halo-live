import test from "node:test";
import assert from "node:assert/strict";
import {decideWorkflowTransition as decide, WORKFLOW_ACTIONS} from "./transition-decision.mjs";
const baseSession={authenticated:true,tenantID:"tenant-a",actorID:"manager-a",roles:["manager"],industryIDs:["construction"]};
const item={id:"job-1",tenantID:"tenant-a",industryID:"construction",templateID:"dispatch",templateVersion:2,state:"created",revision:0,assigneeID:"crew-a"};
const run=(overrides={})=>decide({session:baseSession,workItem:item,action:"assign",expectedRevision:0,...overrides});
test("valid decision carries pinned template and revision, no mutations",()=>{
 const before=structuredClone(item);
 const decision=run();
 assert.equal(decision.allowed,true);
 assert.deepEqual(decision.transition,{workItemID:"job-1",tenantID:"tenant-a",industryID:"construction",templateID:"dispatch",templateVersion:2,actorID:"manager-a",action:"assign",from:"created",to:"assigned",previousRevision:0,nextRevision:1});
 assert.deepEqual(item,before);
 assert.equal(Object.isFrozen(decision.transition),true);
});
test("rejects scope, missing identity, revision drift and unsupported action",()=>{
 for(const input of [
  {session:{...baseSession,tenantID:"tenant-b"}},
  {session:{...baseSession,industryIDs:["transport"]}},
  {session:{...baseSession,authenticated:false}},
  {expectedRevision:1},
  {expectedRevision:-1},
  {action:"delete_everything"}
 ]) assert.equal(run(input).allowed,false);
});
test("enforces role, assignee, and approval separation",()=>{
 assert.equal(run({session:{...baseSession,roles:["crew"]}}).code,"FORBIDDEN_ROLE");
 const accepted={...item,state:"assigned",revision:1};
 const employee={...baseSession,actorID:"crew-a",roles:["assignee"]};
 assert.equal(run({workItem:accepted,action:"accept",expectedRevision:1,session:employee}).allowed,true);
 assert.equal(run({workItem:accepted,action:"accept",expectedRevision:1,session:{...employee,actorID:"crew-b"}}).code,"FORBIDDEN_ASSIGNEE");
 const approval={...item,state:"review_pending",revision:5};
 assert.equal(run({workItem:approval,action:"approve",expectedRevision:5,session:{...employee,roles:["approver"]}}).code,"SEPARATION_OF_DUTIES");
});
test("all three evidence-gated transitions require server-verified scoped evidence",()=>{
 for(const [action,state,role,actor] of [
  ["submit_evidence","in_progress","assignee","crew-a"],
  ["approve","review_pending","approver","approver-b"],
  ["close","approved","manager","manager-a"]
 ]) {
  const workItem={...item,state,revision:2};
  const session={...baseSession,roles:[role],actorID:actor};
  const args={workItem,session,action,expectedRevision:2};
  assert.equal(run(args).code,"EVIDENCE_REQUIRED");
  assert.equal(run({...args,evidence:{serverVerified:true,tenantID:"tenant-b",workItemID:"job-1",verificationID:"proof-1"}}).code,"EVIDENCE_REQUIRED");
  assert.equal(run({...args,evidence:{serverVerified:true,tenantID:"tenant-a",workItemID:"job-1",verificationID:"proof-1"}}).allowed,true);
 }
});
test("disallows skipping steps, terminal transitions, and overflow",()=>{
 assert.equal(WORKFLOW_ACTIONS.length,7);
 assert.equal(run({action:"close"}).code,"INVALID_TRANSITION");
 assert.equal(run({workItem:{...item,state:"closed"},action:"assign"}).code,"INVALID_TRANSITION");
 assert.equal(run({workItem:{...item,revision:Number.MAX_SAFE_INTEGER},expectedRevision:Number.MAX_SAFE_INTEGER}).code,"REVISION_EXHAUSTED");
});
