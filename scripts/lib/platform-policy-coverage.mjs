import assert from 'node:assert/strict';

// Test-runner bookkeeping only. These receipts grant no runtime authority.
export function validatePolicyPlan(plan){
  assert(Array.isArray(plan)&&plan.length>0&&plan.length<=256);
  assert(plan.every(name=>typeof name==='string'&&name.length>0&&name.length<=128));
  assert.equal(new Set(plan).size,plan.length);
  return plan;
}

export function verifyPolicyCoverage(plan,records){
  validatePolicyPlan(plan);
  assert(Array.isArray(records)&&records.length===2);
  const completed=[];
  for(const [partition,record] of records.entries()){
    assert(record&&typeof record==='object'&&!Array.isArray(record));
    assert.deepEqual(Object.keys(record).sort(),['version','partition','partitions','checks','completed'].sort());
    assert.equal(record.version,1);assert.equal(record.partition,partition);assert.equal(record.partitions,2);
    assert.deepEqual(record.checks,plan.filter((_,index)=>index%2===partition));
    assert.equal(record.completed,record.checks.length);
    completed.push(...record.checks);
  }
  assert.equal(completed.length,plan.length);
  assert.deepEqual(completed.toSorted(),plan.toSorted());
}
