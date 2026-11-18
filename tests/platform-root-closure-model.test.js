import assert from 'node:assert/strict';
import { test } from 'node:test';

// Executable design model only. Neither its handles nor its closure predicate
// are used by the manager, native tracker, journal, or admission process.
class RootClosureModel {
  #roots = new Map();
  #operations = new Map();
  #capacity;

  constructor(capacity = 8) { this.#capacity = capacity; }

  register(epoch, correlation, sequence) {
    const key = JSON.stringify([epoch, correlation, sequence]);
    assert(!this.#roots.has(key));
    this.#roots.set(key, { open: true, live: 0 });
    return key;
  }

  close(key) { this.#roots.get(key).open = false; }

  begin(key) {
    if (!this.#roots.get(key)?.open) return null;
    return this.#publish(new Set([key]));
  }

  inherit(parents) {
    if (!parents.length || parents.some(parent => !this.#operations.has(parent))) return null;
    const keys = new Set(parents.flatMap(parent => [...this.#operations.get(parent)]));
    return this.#publish(keys);
  }

  #publish(keys) {
    // Refusal is before publication and cannot consume a parent's hold.
    if (this.#operations.size >= this.#capacity) return null;
    const handle = Symbol();
    this.#operations.set(handle, keys);
    for (const key of keys) this.#roots.get(key).live++;
    return handle;
  }

  release(handle) {
    const keys = this.#operations.get(handle);
    if (!keys) return false;
    this.#operations.delete(handle);
    for (const key of keys) this.#roots.get(key).live--;
    return true;
  }

  closed(key) {
    const root = this.#roots.get(key);
    return root?.open === false && root.live === 0;
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
  assert.notEqual(retry, first);
  assert.equal(model.inherit([first]), null);
  assert(model.release(parent));
  assert.equal(model.closed(root), false);
  assert(model.release(retry));
  assert.equal(model.closed(root), true);
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
