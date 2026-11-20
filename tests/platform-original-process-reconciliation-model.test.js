import assert from 'node:assert/strict';
import test from 'node:test';

// Contract model only. No process observer, durable receipt or live resolver.
const processA = {boot: 'boot-a', pid: 42, start: 'start-a', artifact: 'artifact-a'};
const processB = {...processA, start: 'start-b'};
const scopeA = {nativeEpoch: 'native-a', process: processA};
const scopeB = {nativeEpoch: 'native-b', process: processB};
const sameProcess = (a,b) => Number.isSafeInteger(a.pid) && a.pid > 1 && a.pid === b.pid &&
  ['boot','start','artifact'].every(field => typeof a[field] === 'string' && a[field].length > 0 && a[field] === b[field]);

function reconcilesOriginal(scope, witness) {
  if (!scope.process || !witness?.process || witness.kind !== 'independent_exact_process_absence' || witness.verified !== true) return false;
  return typeof scope.nativeEpoch === 'string' && scope.nativeEpoch.length > 0 && witness.nativeEpoch === scope.nativeEpoch && sameProcess(scope.process,witness.process);
}

const originalAbsence = {kind: 'independent_exact_process_absence', verified: true, nativeEpoch: 'native-a', process: processA};

test('process absence is scoped to the originally bound native epoch and exact process identity', () => {
  assert.equal(reconcilesOriginal(scopeA,originalAbsence),true);
  assert.equal(reconcilesOriginal(scopeB,originalAbsence),false);
  for (const field of ['boot','pid','start','artifact']) {
    const other = {...originalAbsence,process:{...processA,[field]:'different'}};
    assert.equal(reconcilesOriginal(scopeA,other),false,field);
  }
  assert.equal(reconcilesOriginal(scopeA,{...originalAbsence,nativeEpoch:'native-b'}),false);
});

test('observer failure or transport evidence cannot supply an original absence witness', () => {
  for (const kind of ['endpoint_refused','new_listener','local_child_reaped','observer_unavailable']) {
    assert.equal(reconcilesOriginal(scopeA,{...originalAbsence,kind}),false,kind);
  }
  assert.equal(reconcilesOriginal(scopeA,{...originalAbsence,verified:false}),false);
  assert.equal(reconcilesOriginal({nativeEpoch:'native-a'},originalAbsence),false);
  assert.equal(reconcilesOriginal(scopeA,{...originalAbsence,verified:'true'}),false);
  for (const field of ['boot','pid','start','artifact']) {
    const partial = {...processA};delete partial[field];
    assert.equal(reconcilesOriginal({...scopeA,process:partial},{...originalAbsence,process:partial}),false,field);
  }
  assert.equal(reconcilesOriginal({process:processA},{...originalAbsence,nativeEpoch:undefined}),false);
});
