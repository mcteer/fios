import test from "node:test";
import assert from "node:assert/strict";
import { agentApp } from "./agent-support.js";

test("real Agent handles exact local/peer targets, no retries, stream failures and recovery", async () => {
  const app = await agentApp();
  try {
    const peer = app.mock.addPeer();
    for (const [prompt, model, expected] of [
      ["normal", "test/coding-model", "complete"],
      ["DONE_ONLY", peer, "complete"],
      ["USAGE_RESPONSE", peer, "complete"],
      ["FAIL_UPSTREAM", peer, "error"],
      ["RATE_LIMIT", peer, "error"],
      ["MISSING_SENTINEL", peer, "error"],
      ["MALFORMED_STREAM", peer, "error"],
      ["PARTIAL_STREAM", peer, "error"],
      ["TOOL_RESPONSE", peer, "error"],
      ["normal again", peer, "complete"],
    ]) {
      const c = await app.chat();
      const before = app.mock.requests.length;
      const response = await app.send(c.id, prompt, model);
      assert.equal(response.status, 200);
      const stream = await response.text();
      assert.equal(app.mock.requests.length, before + 1, prompt);
      assert.equal(app.mock.requests.at(-1).model, model);
      assert.equal((stream.match(/event: done/g) || []).length, 1, prompt);
      const detail = await (await app.request(`/api/chats/${c.id}`)).json();
      assert.equal(detail.messages.length, 2);
      assert.equal(detail.messages.at(-1).status, expected, prompt);
      assert.equal(detail.generating, false);
      if (expected === "complete") assert.match(stream, /event: delta/);
    }
  } finally {
    await app.close();
  }
});

test("unavailable worker fails before persistence, never bypasses, non-inference remains usable", async () => {
  const app = await agentApp({ python: "/nonexistent/fios-test-python" });
  try {
    const c = await app.chat();
    assert.equal((await app.send(c.id, "must not infer")).status, 503);
    assert.equal(app.mock.requests.length, 0);
    assert.equal(
      (await (await app.request(`/api/chats/${c.id}`)).json()).messages.length,
      0,
    );
    assert.equal((await app.request("/health")).status, 200);
    assert.equal((await app.request("/api/models")).status, 200);
  } finally {
    await app.close();
  }
});
