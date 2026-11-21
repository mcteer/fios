import assert from 'node:assert/strict';
import test from 'node:test';

// A contract model only. IDs represent exact capabilities supplied by a future
// locked tracker/queue handoff, not strings accepted from a native caller.
function reserve({roots, job, epoch, deadline}, now, liveRoots) {
  if (!roots.length || roots.length > 256 || new Set(roots).size !== roots.length || !roots.every(root => liveRoots.has(root)) ||
      !job || !epoch || !Number.isSafeInteger(now) || now < 0 || !Number.isSafeInteger(deadline) || now >= deadline) return null;
  return {roots: Object.freeze([...roots]), job, epoch, deadline, observedAt: now, phase: 'staged'};
}

function transition(owner, event) {
  if (event.job !== owner.job || event.epoch !== owner.epoch || event.roots.length !== owner.roots.length ||
      new Set(event.roots).size !== owner.roots.length || !owner.roots.every(root => event.roots.includes(root))) return owner;
  const beforeExpiry = Number.isSafeInteger(event.now) && event.now >= owner.observedAt && event.now < owner.deadline;
  let phase = owner.phase;
  if (phase === 'staged' && event.kind === 'publish' && beforeExpiry) phase = 'queued';
  else if ((phase === 'queued' || phase === 'between_steps') && event.kind === 'pickup' && beforeExpiry && event.exactModelAvailable) phase = 'acquired';
  else if ((phase === 'queued' || phase === 'staged') && event.kind === 'withdraw' && event.exactNonDispatch) phase = 'retired';
  else if (phase === 'acquired' && event.kind === 'relinquish_step_guard' && event.checkedStepRetirement) phase = 'between_steps';
  else if ((phase === 'acquired' || phase === 'between_steps') && event.kind === 'retire' && event.checkedRetirement) phase = 'retired';
  else if ((phase === 'acquired' || phase === 'between_steps') && event.kind === 'refuse') phase = 'held';
  return phase === owner.phase ? owner : {...owner, phase, observedAt: beforeExpiry ? event.now : owner.observedAt};
}

const original = {roots: [Symbol('original'), Symbol('joined')], job: Symbol('queue item'), epoch: Symbol('process'), deadline: 30};
const make = () => reserve(original, 10, new Set(original.roots));
const apply = (owner, kind, options = {}) => transition(owner, {
  ...original, kind, now: 20, exactModelAvailable: true, ...options,
});

test('idle warm reserves the original live root before queue publication', () => {
  const live = new Set(original.roots);
  const staged = reserve(original, 10, live);
  live.delete(original.roots[0]); // caller can respond after the live child is reserved
  assert.equal(reserve(original, 11, live), null);
  assert.equal(reserve(original, 30, new Set(original.roots)), null);
  const queued = apply(staged, 'publish');
  const acquired = apply(queued, 'pickup');
  assert.equal(acquired.phase, 'acquired');
  assert.deepEqual(acquired.roots, original.roots);
  assert.equal(acquired.deadline, original.deadline);
});

test('idle warm does not retain an empty, oversized or duplicate origin group', () => {
  const oversized = Array.from({length: 257}, (_, index) => Symbol(String(index)));
  for (const roots of [[], [original.roots[0], original.roots[0]], oversized]) {
    assert.equal(reserve({...original, roots}, 10, new Set(roots)), null);
  }
  const roots = [...original.roots];
  const staged = reserve({...original, roots}, 10, new Set(roots));
  roots.pop();
  assert.deepEqual(staged.roots, original.roots);
});

test('idle expiry fences pickup but does not discharge the exact queued owner', () => {
  const queued = apply(make(), 'publish');
  for (const now of [19, 30, 31, NaN]) assert.equal(apply(queued, 'pickup', {now}), queued);
  assert.equal(apply(queued, 'withdraw', {now: 31}), queued);
  const retired = apply(queued, 'withdraw', {now: 31, exactNonDispatch: true});
  assert.equal(retired.phase, 'retired');
  assert.equal(apply(retired, 'pickup'), retired);
});

test('eviction blocks pickup without silently releasing the queued parent', () => {
  const queued = apply(make(), 'publish');
  assert.equal(apply(queued, 'pickup', {exactModelAvailable: false}), queued);
  const retired = apply(queued, 'withdraw', {exactNonDispatch: true});
  assert.equal(retired.phase, 'retired');
  assert.equal(apply(retired, 'pickup'), retired);
});

test('idle pickup wins over withdrawal; only checked retirement can discharge it', () => {
  const acquired = apply(apply(make(), 'publish'), 'pickup');
  assert.equal(apply(acquired, 'withdraw', {now: 31, exactNonDispatch: true}), acquired);
  assert.equal(apply(acquired, 'retire', {now: 40}), acquired);
  assert.equal(apply(acquired, 'retire', {now: 40, checkedRetirement: true}).phase, 'retired');
});

test('checked step guard release does not settle the original lineage or cache', () => {
  const acquired = apply(apply(make(), 'publish'), 'pickup');
  assert.equal(apply(acquired, 'relinquish_step_guard'), acquired);
  const between = apply(acquired, 'relinquish_step_guard', {checkedStepRetirement: true});
  assert.equal(between.phase, 'between_steps');
  assert.equal(apply(between, 'withdraw', {exactNonDispatch: true}), between);
  assert.equal(apply(between, 'pickup', {now: 30}), between);
  assert.equal(apply(between, 'pickup', {now: 25}).phase, 'acquired');
  assert.equal(apply(between, 'retire', {now: 31, checkedRetirement: true}).phase, 'retired');
});

test('idle refusal holds the exact owner despite expiry or later apparent success', () => {
  const acquired = apply(apply(make(), 'publish'), 'pickup');
  assert.equal(apply(acquired, 'retire', {roots: [original.roots[0]], checkedRetirement: true}), acquired);
  assert.equal(apply(acquired, 'retire', {roots: [original.roots[0], original.roots[0]], checkedRetirement: true}), acquired);
  for (const key of ['job', 'epoch']) {
    assert.equal(apply(acquired, 'retire', {[key]: Symbol('foreign'), checkedRetirement: true}), acquired);
  }
  const held = apply(acquired, 'refuse');
  assert.equal(held.phase, 'held');
  assert.equal(apply(held, 'retire', {checkedRetirement: true, now: 40}), held);
  assert.equal(apply(held, 'withdraw', {exactNonDispatch: true, now: 40}), held);
});
