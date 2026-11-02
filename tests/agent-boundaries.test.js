import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { AgentClient } from "../src/agent/client.js";
import { agentApp } from "./agent-support.js";
import { mockMlx } from "./mock-mlx.js";

test("real worker stops slow/no-token streams, preserves partial answer, and recovers", async () => {
  const app = await agentApp();
  try {
    for (const prompt of ["SLOW_RESPONSE", "NO_FIRST_TOKEN"]) {
      const c = await app.chat();
      const response = await app.send(c.id, prompt);
      const reader = response.body.getReader();
      let text = "";
      while (
        !text.includes(
          prompt === "SLOW_RESPONSE" ? "event: delta" : "event: meta",
        )
      ) {
        const { value, done } = await reader.read();
        assert.equal(done, false);
        text += new TextDecoder().decode(value);
      }
      const start = Date.now();
      await app.request(`/api/chats/${c.id}/stop`, { method: "POST" });
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        text += new TextDecoder().decode(value);
      }
      const detail = await (await app.request(`/api/chats/${c.id}`)).json();
      assert.equal(detail.generating, false);
      assert.equal(detail.messages.at(-1).status, "interrupted");
      assert.ok(Date.now() - start < 2000);
      for (let i = 0; i < 20 && !app.mock.connections.at(-1).closed; i++)
        await new Promise((r) => setTimeout(r, 10));
      assert.ok(app.mock.connections.at(-1).closed);
      if (prompt === "SLOW_RESPONSE")
        assert.ok(detail.messages.at(-1).content.length > 0);
    }
    const c = await app.chat();
    await (await app.send(c.id, "after cancellation")).text();
    assert.equal(
      (await (await app.request(`/api/chats/${c.id}`)).json()).messages.at(-1)
        .status,
      "complete",
    );
  } finally {
    await app.close();
  }
});

test("idle watchdog observes actual data, not synthetic keepalives; worker can restart after crash", async () => {
  const mock = await mockMlx();
  // Readiness must not start the short upstream-data watchdog measurement.
  // A delayed probe makes the old generic HTTP request handshake fail reliably.
  mock.health.delayMs = 500;
  const client = new AgentClient({
    env: { MLX_BASE_URL: mock.url },
    idleMs: 10000,
  });
  try {
    await client.ready();
    const events = [];
    const received = once(mock.server, "model-request", {
      signal: AbortSignal.timeout(10000),
    });
    const firstRun = (async () => {
      for await (const e of client.run({
        model: "test/coding-model",
        context: [{ role: "user", content: "NO_FIRST_TOKEN" }],
      }))
        events.push(e);
    })();
    await Promise.race([
      received,
      firstRun.then(() => {
        throw new Error("Idle run ended before reaching mock MLX");
      }),
    ]);
    // Measure upstream idleness, not variable cold HTTP/Agent initialization time.
    client.options.idleMs = 300;
    const idleStart = Date.now();
    client.resetIdle(client.current);
    await firstRun;
    assert.equal(events.at(-1).status, "interrupted");
    assert.ok(Date.now() - idleStart >= 250);
    assert.ok(Date.now() - idleStart < 2300);
    await client.ready();
    const crashed = client.worker;
    process.kill(client.pid, "SIGKILL");
    await crashed.exit;
    client.options.idleMs = 10000;
    const next = [];
    for await (const e of client.run({
      model: "test/coding-model",
      context: [{ role: "user", content: "normal" }],
    }))
      next.push(e);
    assert.equal(next.at(-1).status, "complete");
    assert.equal(mock.requests.length, 2);
  } finally {
    await client.close();
    mock.server.closeAllConnections();
    await new Promise((r) => mock.server.close(r));
  }
});

test("maximum image/Unicode context remains bounded and preserves bytes through real harness", async () => {
  const mock = await mockMlx();
  const client = new AgentClient({ env: { MLX_BASE_URL: mock.url } });
  try {
    const image = Buffer.alloc(10 * 1024 * 1024, 120);
    Buffer.from("89504e470d0a1a0a", "hex").copy(image);
    const url = "data:image/png;base64," + image.toString("base64");
    const context = [
      {
        role: "user",
        content: [
          { type: "text", text: "🧵".repeat(200000) },
          { type: "image_url", image_url: { url } },
          { type: "image_url", image_url: { url } },
        ],
      },
    ];
    let done = false;
    for await (const e of client.run({ model: "test/coding-model", context }))
      if (e.type === "done") done = true;
    assert.ok(done);
    assert.equal(
      mock.requests[0].messages.at(-1).content[1].image_url.url,
      url,
    );
    assert.throws(() =>
      client.validate({
        model: "test/coding-model",
        context: [{ role: "user", content: "x".repeat(33 * 1024 * 1024) }],
      }),
    );
  } finally {
    await client.close();
    mock.server.closeAllConnections();
    await new Promise((r) => mock.server.close(r));
  }
});
