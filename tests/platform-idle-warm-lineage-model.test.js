import assert from 'node:assert/strict';
import test from 'node:test';

// A contract model only. IDs represent exact capabilities supplied by a future
// locked tracker/queue handoff, not strings accepted from a native caller.
function reserve({roots, job, epoch, deadline, cache}, now, liveRoots) {
  if (!roots.length || roots.length > 256 || new Set(roots).size !== roots.length || !roots.every(root => liveRoots.has(root)) ||
      !job || !epoch || !cache || !Number.isSafeInteger(now) || now < 0 || !Number.isSafeInteger(deadline) || now >= deadline) return null;
  return {roots: Object.freeze([...roots]), job, epoch, cache, deadline, observedAt: now, worker: 0, phase: 'staged'};
}

function transition(owner, event) {
  if (event.job !== owner.job || event.epoch !== owner.epoch || event.roots.length !== owner.roots.length ||
      new Set(event.roots).size !== owner.roots.length || !owner.roots.every(root => event.roots.includes(root))) return owner;
  const beforeExpiry = Number.isSafeInteger(event.now) && event.now >= owner.observedAt && event.now < owner.deadline;
  let {phase, worker} = owner;
  if (phase === 'staged' && event.kind === 'publish' && beforeExpiry) phase = 'queued';
  else if ((phase === 'queued' || phase === 'between_steps') && event.kind === 'pickup' && beforeExpiry &&
           event.exactModelAvailable && Number.isSafeInteger(event.worker) && event.worker > worker) {
    phase = 'acquired';
    worker = event.worker;
  } else if ((phase === 'queued' || phase === 'staged') && event.kind === 'withdraw' && event.exactNonDispatch) phase = 'retired';
  else if (phase === 'acquired' && event.kind === 'relinquish_step_guard' && event.worker === worker &&
           event.checkedStepRetirement && event.callbackPublicationClosed) phase = 'between_steps';
  else if (phase === 'between_steps' && event.kind === 'retire' && event.worker === worker &&
           event.cache === owner.cache && event.checkedCacheRetirement && event.callbackPublicationClosed) phase = 'retired';
  else if ((phase === 'acquired' || phase === 'between_steps') && event.kind === 'refuse') phase = 'held';
  return phase === owner.phase ? owner : {...owner, phase, worker, observedAt: beforeExpiry ? event.now : owner.observedAt};
}

const original = {roots: [Symbol('original'), Symbol('joined')], job: Symbol('queue item'),
  epoch: Symbol('process'), cache: Symbol('original cache'), deadline: 30};
const stepReceipt = {checkedStepRetirement: true, callbackPublicationClosed: true};
const cacheReceipt = {checkedCacheRetirement: true, callbackPublicationClosed: true};
const make = () => reserve(original, 10, new Set(original.roots));
const apply = (owner, kind, options = {}) => transition(owner, {
  ...original, kind, now: 20, worker: kind === 'pickup' ? owner.worker + 1 : owner.worker, exactModelAvailable: true, ...options,
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
  assert.equal(apply(acquired, 'retire', {now: 40, ...cacheReceipt}), acquired);
  const between = apply(acquired, 'relinquish_step_guard', {now: 40, ...stepReceipt});
  assert.equal(apply(between, 'retire', {now: 40, ...cacheReceipt}).phase, 'retired');
});

test('checked step guard release does not settle the original lineage or cache', () => {
  const acquired = apply(apply(make(), 'publish'), 'pickup');
  assert.equal(apply(acquired, 'relinquish_step_guard'), acquired);
  const between = apply(acquired, 'relinquish_step_guard', stepReceipt);
  assert.equal(between.phase, 'between_steps');
  assert.equal(apply(between, 'withdraw', {exactNonDispatch: true}), between);
  assert.equal(apply(between, 'pickup', {now: 30}), between);
  assert.equal(apply(between, 'pickup', {now: 25, worker: acquired.worker}), between);
  const next = apply(between, 'pickup', {now: 25});
  assert.equal(next.phase, 'acquired');
  assert.equal(apply(next, 'relinquish_step_guard', {...stepReceipt, worker: acquired.worker}), next);
  assert.equal(apply(between, 'retire', {now: 31, ...cacheReceipt}).phase, 'retired');
});

// The SDK may reuse an already retained context without taking another
// tracker reference. Publication must still reserve against the producer
// gate. Outstanding permits survive gate closure until an exact receipt.
function producerTransition(producer, {worker, kind, permit, checked = false}) {
  if (worker !== producer.worker) return producer;
  if (kind === 'reserve' && producer.open && Number.isSafeInteger(permit) &&
      permit > producer.lastPermit && producer.pending.length < 2) {
    return {...producer, lastPermit: permit, pending: [...producer.pending, permit]};
  }
  if (kind === 'close' && producer.open) return {...producer, open: false};
  if (kind === 'retire' && checked && producer.pending.includes(permit)) {
    return {...producer, pending: producer.pending.filter(value => value !== permit)};
  }
  return producer;
}

test('reused SDK contexts cannot bypass the producer publication gate', () => {
  const initial = {worker: 7, open: true, lastPermit: 0, pending: []};
  const reserved = producerTransition(initial, {worker: 7, kind: 'reserve', permit: 1});
  const second = producerTransition(reserved, {worker: 7, kind: 'reserve', permit: 2});
  assert.equal(producerTransition(second, {worker: 7, kind: 'reserve', permit: 3}), second);
  const closing = producerTransition(second, {worker: 7, kind: 'close'});
  assert.equal(closing.open, false);
  assert.deepEqual(closing.pending, [1, 2]);
  assert.equal(producerTransition(closing, {worker: 7, kind: 'reserve', permit: 3}), closing);
  assert.equal(producerTransition(closing, {worker: 6, kind: 'retire', permit: 1, checked: true}), closing);
  assert.equal(producerTransition(closing, {worker: 7, kind: 'retire', permit: 1}), closing);
  const partlyRetired = producerTransition(closing, {worker: 7, kind: 'retire', permit: 1, checked: true});
  assert.deepEqual(partlyRetired.pending, [2]);
  assert.equal(producerTransition(partlyRetired, {worker: 7, kind: 'retire', permit: 1, checked: true}), partlyRetired);
  const closed = producerTransition(partlyRetired, {worker: 7, kind: 'retire', permit: 2, checked: true});
  assert.deepEqual(closed.pending, []);
  assert.equal(closed.open, false);
});

test('a non-slot sweep still needs checked step and cache callback closure', () => {
  const acquired = apply(apply(make(), 'publish'), 'pickup');
  assert.equal(apply(acquired, 'relinquish_step_guard', {checkedStepRetirement: true}), acquired);
  const between = apply(acquired, 'relinquish_step_guard', stepReceipt);
  assert.equal(apply(between, 'retire', {checkedCacheRetirement: true}), between);
  assert.equal(apply(between, 'retire', {...cacheReceipt, cache: Symbol('other cache')}), between);
  assert.equal(apply(between, 'retire', cacheReceipt).phase, 'retired');
});

test('idle refusal holds the exact owner despite expiry or later apparent success', () => {
  const between = apply(apply(apply(make(), 'publish'), 'pickup'), 'relinquish_step_guard', stepReceipt);
  assert.equal(apply(between, 'retire', {...cacheReceipt, roots: [original.roots[0]]}), between);
  assert.equal(apply(between, 'retire', {...cacheReceipt, roots: [original.roots[0], original.roots[0]]}), between);
  for (const key of ['job', 'epoch']) {
    assert.equal(apply(between, 'retire', {...cacheReceipt, [key]: Symbol('foreign')}), between);
  }
  const held = apply(between, 'refuse');
  assert.equal(held.phase, 'held');
  assert.equal(apply(held, 'retire', {...cacheReceipt, now: 40}), held);
  assert.equal(apply(held, 'withdraw', {exactNonDispatch: true, now: 40}), held);
});
