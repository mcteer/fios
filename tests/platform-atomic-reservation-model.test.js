import assert from 'node:assert/strict';
import { test } from 'node:test';

// Serial model of an atomic native boundary, not an installed admission issuer.
class Gate {
  #revision = 0;
  #epoch = Symbol();
  #clock = 0;
  #owners = new Map();
  #covered;
  #fenced = false;

  constructor({ covered = false } = {}) { this.#covered = covered; }
  observe(target) { return Object.freeze({ epoch: this.#epoch, revision: this.#revision, target }); }
  fence() { this.#fenced = true; this.#revision++; }
  advance(tick) { assert(tick >= this.#clock); this.#clock = tick; }

  reserve(observation, target) {
    if (observation?.epoch !== this.#epoch || observation.revision !== this.#revision ||
        observation.target !== target || !this.#covered) return null;
    return this.#enter(target);
  }

  external(target) { return this.#enter(target, 'published'); }

  #enter(target, state = 'reserved') {
    if (this.#fenced || [...this.#owners.values()].some(owner => owner.target !== target)) return null;
    const hold = Symbol();
    this.#owners.set(hold, { target, state, receipt: null, expires: this.#clock + 5 });
    this.#revision++;
    return hold;
  }

  publish(hold) {
    const owner = this.#owners.get(hold);
    if (this.#fenced || owner?.state !== 'reserved' || this.#clock >= owner.expires) return false;
    owner.state = 'published';
    this.#revision++;
    return true;
  }

  cancelBeforePublication(hold) {
    if (this.#owners.get(hold)?.state !== 'reserved') return false;
    return this.#remove(hold);
  }

  // A simulated backend event, not callable by the manager in a real design.
  backendTerminal(hold) {
    const owner = this.#owners.get(hold);
    if (this.#fenced || owner?.state !== 'published') return null;
    owner.state = 'terminal';
    owner.receipt = Symbol();
    return owner.receipt;
  }

  releaseTerminal(hold, receipt) {
    const owner = this.#owners.get(hold);
    if (this.#fenced || owner?.state !== 'terminal' || owner.receipt !== receipt) return false;
    return this.#remove(hold);
  }

  #remove(hold) {
    this.#owners.delete(hold);
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
  assert(gate.releaseTerminal(external, gate.backendTerminal(external)));
  assert(gate.reserve(gate.observe('model/b'), 'model/b'));
});

test('reservation blocks conflicting external publication until its exact hold retires', () => {
  const gate = new Gate({ covered: true });
  const reservation = gate.reserve(gate.observe('model/a'), 'model/a');
  const compatible = gate.external('model/a');
  assert(reservation && compatible);
  assert.equal(gate.external('model/b'), null);
  assert(gate.cancelBeforePublication(reservation));
  assert.equal(gate.cancelBeforePublication(reservation), false);
  assert.equal(gate.external('model/b'), null);
  assert(gate.releaseTerminal(compatible, gate.backendTerminal(compatible)));
  assert(gate.external('model/b'));
});

test('no known conflict is insufficient when coverage is unknown or later fenced', () => {
  const unknown = new Gate();
  assert.equal(unknown.reserve(unknown.observe('model/a'), 'model/a'), null);
  const gate = new Gate({ covered: true });
  const hold = gate.reserve(gate.observe('model/a'), 'model/a');
  assert(hold);
  gate.fence();
  assert(gate.cancelBeforePublication(hold));
  assert.equal(gate.reserve(gate.observe('model/a'), 'model/a'), null);
});

test('published work retains custody until a matching terminal receipt', () => {
  const gate = new Gate({ covered: true });
  const hold = gate.reserve(gate.observe('model/a'), 'model/a');
  assert(gate.publish(hold));
  assert.equal(gate.publish(hold), false);
  assert.equal(gate.cancelBeforePublication(hold), false);
  assert.equal(gate.releaseTerminal(hold, null), false);
  assert.equal(gate.external('model/b'), null);
  const sibling = gate.external('model/a');
  const foreign = gate.backendTerminal(sibling);
  const terminal = gate.backendTerminal(hold);
  assert.equal(gate.releaseTerminal(hold, foreign), false);
  assert(gate.releaseTerminal(hold, terminal));
  assert.equal(gate.releaseTerminal(hold, terminal), false);
  assert.equal(gate.external('model/b'), null);
  assert(gate.releaseTerminal(sibling, foreign));
  assert(gate.external('model/b'));
});

test('lease expiry prevents late publication but never releases already published work', () => {
  const gate = new Gate({ covered: true });
  const unused = gate.reserve(gate.observe('model/a'), 'model/a');
  const published = gate.reserve(gate.observe('model/a'), 'model/a');
  assert(gate.publish(published));
  gate.advance(5);
  assert.equal(gate.publish(unused), false);
  assert(gate.cancelBeforePublication(unused));
  assert.equal(gate.cancelBeforePublication(published), false);
  assert.equal(gate.external('model/b'), null);
  assert(gate.releaseTerminal(published, gate.backendTerminal(published)));
  assert(gate.external('model/b'));
});

test('source fence prevents release even after a candidate receipt', () => {
  const gate = new Gate({ covered: true });
  const hold = gate.external('model/a');
  const terminal = gate.backendTerminal(hold);
  assert(terminal);
  gate.fence();
  assert.equal(gate.releaseTerminal(hold, terminal), false);
  assert.equal(gate.cancelBeforePublication(hold), false);
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
