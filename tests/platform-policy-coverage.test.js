import test from 'node:test';
import assert from 'node:assert/strict';
import {validatePolicyPlan,verifyPolicyCoverage} from '../scripts/lib/platform-policy-coverage.mjs';

const plan=['source continuity','worker recovery','admission bounds','native uncertainty'];
const receipts=()=>[0,1].map(partition=>({version:1,partition,partitions:2,
  checks:plan.filter((_,index)=>index%2===partition),completed:2}));

test('both bounded executions must cover the complete named plan exactly once',()=>{
  verifyPolicyCoverage(plan,receipts());
  assert.throws(()=>verifyPolicyCoverage(plan,receipts().slice(0,1)));
  assert.throws(()=>verifyPolicyCoverage(plan,[receipts()[0],receipts()[0]]));
  const missing=receipts();missing[1].checks.pop();missing[1].completed--;
  assert.throws(()=>verifyPolicyCoverage(plan,missing));
  const repeated=receipts();repeated[1].checks[0]=repeated[0].checks[0];
  assert.throws(()=>verifyPolicyCoverage(plan,repeated));
});

test('stale, contradictory and unknown execution receipts cannot report success',()=>{
  for(const change of [r=>{r[0].completed=0;},r=>{r[1].partitions=3;},r=>{r[0].version=2;},
    r=>{r[1].checks.reverse();},r=>{r[0].skipped=[];}]){
    const records=receipts();change(records);assert.throws(()=>verifyPolicyCoverage(plan,records));
  }
  assert.throws(()=>verifyPolicyCoverage([...plan,'new required check'],receipts()));
  for(const invalid of [[],['duplicate','duplicate'],[null],new Array(257).fill('too many')]){
    assert.throws(()=>validatePolicyPlan(invalid));
  }
});
