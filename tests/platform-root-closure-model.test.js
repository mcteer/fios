import assert from 'node:assert/strict';
import { test } from 'node:test';

// Executable design model only. Neither its handles nor its closure predicate
// are used by the manager, native tracker, journal, or admission process.
class RootClosureModel {
  #roots = new Map();
  #slots;
  #identity = Symbol('operation table');
  #maxGeneration;
  #backgroundUntracked = false;

  constructor(capacity = 8, maxGeneration = Number.MAX_SAFE_INTEGER) {
    this.#slots = Array.from({ length: capacity }, () => ({ generation: 0, keys: null }));
    this.#maxGeneration = maxGeneration;
  }

  #live(handle) {
    if (handle?.table !== this.#identity) return null;
    const slot = this.#slots[handle.slot];
    return slot?.generation === handle.generation && slot.keys !== null ? slot : null;
  }

  register(epoch, correlation, sequence) {
    const key = JSON.stringify([epoch, correlation, sequence]);
    assert(!this.#roots.has(key));
    this.#roots.set(key, { open: true, live: 0 });
    return key;
  }

  close(key) { this.#roots.get(key).open = false; }

  fence(key) { this.#roots.get(key).fenced = true; }

  noteUnattributedBackground() { this.#backgroundUntracked = true; }

  // A negative diagnostic only. False is not positive coverage.
  hasBackgroundCoverageGap() { return this.#backgroundUntracked; }

  begin(key) {
    if (!this.#roots.get(key)?.open) return null;
    return this.#publish(new Set([key]));
  }

  inherit(parents) {
    const live = parents.map(parent => this.#live(parent));
    if (!live.length || live.some(slot => slot === null)) return null;
    const keys = new Set(live.flatMap(slot => [...slot.keys]));
    return this.#publish(keys);
  }

  #publish(keys) {
    // Refusal is before publication and cannot consume a parent's hold.
    const index = this.#slots.findIndex(slot => slot.keys === null && slot.generation < this.#maxGeneration);
    if (index < 0) return null;
    const slot = this.#slots[index];
    slot.keys = keys;
    const handle = Object.freeze({ table: this.#identity, slot: index, generation: ++slot.generation });
    for (const key of keys) this.#roots.get(key).live++;
    return handle;
  }

  release(handle) {
    const slot = this.#live(handle);
    if (!slot) return false;
    for (const key of slot.keys) this.#roots.get(key).live--;
    slot.keys = null;
    return true;
  }

  closed(key) {
    const root = this.#roots.get(key);
    return root?.open === false && !root.fenced && root.live === 0;
  }
}

test('closed roots reject independent publication but permit live-parent callbacks', () => {
  const model = new RootClosureModel();
  const root = model.register('epoch-a', 'request', 1);
  const independent = model.begin(root);
  model.close(root);
  assert.equal(model.begin(root), null);
  const deferredCancel = model.inherit([independent]);
  assert(deferredCancel);
  assert(model.release(independent));
  assert.equal(model.closed(root), false);
  assert.equal(model.inherit([independent]), null);
  const callback = model.inherit([deferredCancel]);
  assert(callback);
  assert(model.release(deferredCancel));
  assert.equal(model.closed(root), false);
  assert(model.release(callback));
  assert.equal(model.release(callback), false);
  assert.equal(model.inherit([callback]), null);
  assert.equal(model.closed(root), true);
  assert.equal(model.closed(model.register('epoch-b', 'request', 1)), false);
  assert.equal(model.closed(model.register('epoch-a', 'request', 2)), false);
});

test('device completion cannot seal a root before callback capture destruction', () => {
  const model = new RootClosureModel();
  const root = model.register('epoch', 'request', 1);
  const buffer = model.begin(root);
  const callback = model.inherit([buffer]);
  model.close(root);
  assert(model.release(buffer)); // The device completed; its callback is still live.
  assert.equal(model.closed(root), false);
  const destructorWork = model.inherit([callback]);
  assert(destructorWork);
  assert(model.release(callback));
  assert.equal(model.inherit([callback]), null);
  assert.equal(model.closed(root), false);
  assert(model.release(destructorWork));
  assert.equal(model.closed(root), true);
});

test('capacity refusal leaves parent custody intact and retired handles cannot be reused', () => {
  const model = new RootClosureModel(2);
  const root = model.register('epoch', 'request', 1);
  const parent = model.begin(root);
  const first = model.inherit([parent]);
  model.close(root);
  assert.equal(model.inherit([parent]), null);
  assert(model.release(first));
  const retry = model.inherit([parent]);
  assert(retry);
  assert.equal(retry.slot, first.slot);
  assert.equal(retry.generation, first.generation + 1);
  assert.equal(model.inherit([first]), null);
  assert(model.release(parent));
  assert.equal(model.closed(root), false);
  assert(model.release(retry));
  assert.equal(model.closed(root), true);
});

test('an unattributed background gap survives closure of an unrelated tracked root', () => {
  const model = new RootClosureModel();
  const root = model.register('epoch', 'request', 1);
  const operation = model.begin(root);
  model.noteUnattributedBackground();
  model.close(root);
  assert(model.release(operation));
  assert.equal(model.closed(root), true); // Tracked model only, never a native receipt.
  assert.equal(model.hasBackgroundCoverageGap(), true);
});

test('escaped publication remains fenced after all tracked references retire', () => {
  const model = new RootClosureModel(1);
  const root = model.register('epoch', 'request', 1);
  const independent = model.begin(root);
  assert.equal(model.inherit([independent]), null);
  // This caller cannot attest that publication was stopped before refusal.
  model.fence(root);
  model.close(root);
  assert(model.release(independent));
  assert.equal(model.closed(root), false);
});

test('exhausted generation retires the slot without reviving a stale handle', () => {
  const model = new RootClosureModel(1, 2);
  const root = model.register('epoch', 'request', 1);
  const first = model.begin(root);
  assert(model.release(first));
  const second = model.begin(root);
  assert.equal(second.slot, first.slot);
  assert.equal(second.generation, 2);
  const replacement = new RootClosureModel(1, 2);
  const replacementRoot = replacement.register('replacement', 'request', 1);
  const replacementHandle = replacement.begin(replacementRoot);
  assert.equal(replacementHandle.slot, first.slot);
  assert.equal(replacementHandle.generation, first.generation);
  assert.equal(replacement.release(first), false);
  assert.equal(replacement.inherit([first]), null);
  assert.equal(model.release(first), false);
  assert(model.release(second));
  assert.equal(model.begin(root), null);
  model.close(root);
  assert(model.closed(root)); // No work was published by the refused begin.
});

test('mixed-root handoff validates every parent before counting either root', () => {
  const model = new RootClosureModel();
  const a = model.register('epoch', 'request-a', 1);
  const b = model.register('epoch', 'request-b', 2);
  const aParent = model.begin(a);
  const bParent = model.begin(b);
  const batch = model.inherit([aParent, bParent, aParent]);
  assert(batch);
  model.close(a);
  model.close(b);
  assert(model.release(aParent));
  assert.equal(model.inherit([aParent, bParent]), null);
  assert(model.release(bParent));
  assert.equal(model.closed(a), false);
  assert.equal(model.closed(b), false);
  assert(model.release(batch));
  assert.equal(model.closed(a), true);
  assert.equal(model.closed(b), true);
});
