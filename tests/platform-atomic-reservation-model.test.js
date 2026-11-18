import assert from 'node:assert/strict';
import { test } from 'node:test';

// Serial model of an atomic native boundary, not an installed admission issuer.
class Gate {
  #revision = 0;
  #epoch = Symbol();
  #owners = new Map();
  #covered;
  #fenced = false;

  constructor({ covered = false } = {}) { this.#covered = covered; }
  observe(target) { return Object.freeze({ epoch: this.#epoch, revision: this.#revision, target }); }
  fence() { this.#fenced = true; this.#revision++; }

  reserve(observation, target) {
    if (observation?.epoch !== this.#epoch || observation.revision !== this.#revision ||
        observation.target !== target || !this.#covered) return null;
    return this.#enter(target);
  }

  external(target) { return this.#enter(target); }

  #enter(target) {
    if (this.#fenced || [...this.#owners.values()].some(model => model !== target)) return null;
    const hold = Symbol();
    this.#owners.set(hold, target);
    this.#revision++;
    return hold;
  }

  release(hold) {
    if (!this.#owners.delete(hold)) return false;
    this.#revision++;
    return true;
  }
}

test('external arrival between observation and reservation wins without preemption', () => {
  const gate = new Gate({ covered: true });
  const idle = gate.observe('model/b');
  const external = gate.external('model/a');
  assert(external);
  assert.equal(gate.reserve(idle, 'model/b'), null);
  assert.equal(gate.reserve(gate.observe('model/b'), 'model/b'), null);
  assert(gate.release(external));
  assert(gate.reserve(gate.observe('model/b'), 'model/b'));
});

test('reservation blocks conflicting external publication until its exact hold retires', () => {
  const gate = new Gate({ covered: true });
  const reservation = gate.reserve(gate.observe('model/a'), 'model/a');
  const compatible = gate.external('model/a');
  assert(reservation && compatible);
  assert.equal(gate.external('model/b'), null);
  assert(gate.release(reservation));
  assert.equal(gate.release(reservation), false);
  assert.equal(gate.external('model/b'), null);
  assert(gate.release(compatible));
  assert(gate.external('model/b'));
});

test('no known conflict is insufficient when coverage is unknown or later fenced', () => {
  const unknown = new Gate();
  assert.equal(unknown.reserve(unknown.observe('model/a'), 'model/a'), null);
  const gate = new Gate({ covered: true });
  const hold = gate.reserve(gate.observe('model/a'), 'model/a');
  assert(hold);
  gate.fence();
  assert(gate.release(hold));
  assert.equal(gate.reserve(gate.observe('model/a'), 'model/a'), null);
});

test('coincident revision from an old epoch or different target cannot reserve', () => {
  const old = new Gate({ covered: true });
  const gate = new Gate({ covered: true });
  const observation = old.observe('model/a');
  assert.equal(observation.revision, gate.observe('model/a').revision);
  assert.equal(gate.reserve(observation, 'model/a'), null);
  assert.equal(gate.reserve(gate.observe('model/A'), 'model/a'), null);
  assert(gate.reserve(gate.observe('model/a'), 'model/a'));
});
