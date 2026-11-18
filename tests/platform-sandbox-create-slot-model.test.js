import assert from 'node:assert/strict';
import { test } from 'node:test';

// Model only: an executor reservation consumes capacity but does not publish.
class Slots {
  #slots = new Map();
  #journal = new Set();

  reserve(job) {
    if (this.#slots.size >= 2 || this.#slots.has(job) || this.#journal.has(job)) return null;
    const permit = Object.freeze({ job, identity: Symbol() });
    this.#slots.set(job, { permit, state: 'reserved' });
    return permit;
  }

  commit(permit, disposition) {
    const slot = this.#slots.get(permit.job);
    if (slot?.permit !== permit || slot.state !== 'reserved') return false;
    if (disposition !== 'committed') {
      assert(['not_committed', 'unknown'].includes(disposition));
      this.#slots.delete(permit.job);
      if (disposition === 'unknown') this.#journal.add(permit.job);
      return false;
    }
    this.#journal.add(permit.job);
    slot.state = 'committed';
    return true;
  }

  publish(permit) {
    const slot = this.#slots.get(permit.job);
    if (slot?.permit !== permit || slot.state !== 'committed') return false;
    slot.state = 'published';
    return true;
  }
}

test('reservation and failed durable create write publish nothing and refund only their slot', () => {
  const slots = new Slots();
  const a = slots.reserve('a');
  const b = slots.reserve('b');
  assert(a && b);
  assert.equal(slots.reserve('c'), null);
  assert.equal(slots.publish(a), false);
  assert.equal(slots.commit(a, 'not_committed'), false);
  assert.equal(slots.publish(a), false);
  const c = slots.reserve('c');
  assert(c);
  assert.equal(slots.reserve('a'), null);
  assert(slots.commit(b, 'committed'));
  assert(slots.publish(b));
  assert.equal(slots.publish(b), false);
  assert.equal(slots.publish(c), false);
});

test('ambiguous journal outcome fences the job without retaining an unpublished executor slot', () => {
  const slots = new Slots();
  const a = slots.reserve('a');
  const b = slots.reserve('b');
  assert(a && b);
  assert.equal(slots.commit(a, 'unknown'), false);
  assert.equal(slots.publish(a), false);
  assert.equal(slots.reserve('a'), null);
  assert(slots.reserve('c'));
});

test('stale reservation cannot publish after another hold for the same job', () => {
  const slots = new Slots();
  const old = slots.reserve('a');
  assert.equal(slots.commit(old, 'not_committed'), false);
  const current = slots.reserve('a');
  assert(slots.commit(current, 'committed'));
  assert.equal(slots.publish(old), false);
  assert(slots.publish(current));
});
