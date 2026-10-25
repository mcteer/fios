import test from "node:test";
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import { AgentClient } from "../src/agent/client.js";
import { mockMlx } from "./mock-mlx.js";
import { agentApp } from "./agent-support.js";

test("wedged worker ignores TERM but is killed/reaped within stop deadline", async () => {
  const c = new AgentClient({
    args: [
      "-I",
      "-B",
      fileURLToPath(new URL("fixtures/agent-worker.py", import.meta.url)),
      "wedged",
    ],
  });
  const control = new AbortController();
  try {
    const pending = (async () => {
      const out = [];
      for await (const e of c.run(
        { model: "test/model", context: [{ role: "user", content: "hello" }] },
        { signal: control.signal },
      ))
        out.push(e);
      return out;
    })();
    while (!c.pid) await new Promise((r) => setTimeout(r, 5));
    await new Promise((r) => setTimeout(r, 50));
    const start = Date.now();
    control.abort();
    const result = await pending;
    assert.equal(result.at(-1).status, "interrupted");
    assert.ok(Date.now() - start < 2000);
    assert.equal(c.pid, null);
    assert.equal(c.active, false);
  } finally {
    await c.close();
  }
});

test("parent SIGKILL closes inherited pipe and worker exits without an orphan", async () => {
  const parent = spawn(process.execPath, ["tests/fixtures/agent-parent.mjs"], {
    env: { PATH: process.env.PATH, MLX_BASE_URL: "http://127.0.0.1:1/v1" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let text = "";
  const info = await new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("parent fixture not ready")),
      5000,
    );
    parent.stdout.on("data", (b) => {
      text += b;
      if (text.includes("\n")) {
        clearTimeout(timer);
        resolve(JSON.parse(text.split("\n")[0]));
      }
    });
    parent.on("error", reject);
  });
  parent.kill("SIGKILL");
  await once(parent, "exit");
  let alive = true;
  for (let i = 0; i < 100; i++) {
    try {
      process.kill(info.pid, 0);
    } catch {
      alive = false;
      break;
    }
    await new Promise((r) => setTimeout(r, 20));
  }
  assert.equal(alive, false, "worker survived parent death");
});

test("browser disconnect cancels upstream and persists terminal partial state", async () => {
  const app = await agentApp();
  try {
    const c = await app.chat();
    const response = await app.send(c.id, "SLOW_RESPONSE");
    const reader = response.body.getReader();
    let text = "";
    while (!text.includes("event: delta")) {
      const { value } = await reader.read();
      text += new TextDecoder().decode(value);
    }
    await reader.cancel();
    let detail;
    for (let i = 0; i < 100; i++) {
      detail = await (await app.request(`/api/chats/${c.id}`)).json();
      if (!detail.generating) break;
      await new Promise((r) => setTimeout(r, 20));
    }
    assert.equal(detail.generating, false);
    assert.equal(detail.messages.at(-1).status, "interrupted");
    assert.ok(detail.messages.at(-1).content.length);
  } finally {
    await app.close();
  }
});

test("worker crash retains partial answer through app restart without replay", async () => {
  const app = await agentApp();
  try {
    const c = await app.chat();
    const response = await app.send(c.id, "SLOW_RESPONSE");
    const reader = response.body.getReader();
    let text = "";
    while (!text.includes("event: delta")) {
      const n = await reader.read();
      text += new TextDecoder().decode(n.value);
    }
    const children = execFileSync("ps", ["-axo", "pid,ppid"], {
      encoding: "utf8",
    })
      .split("\n")
      .map((s) => s.trim().split(/\s+/).map(Number))
      .filter(([, ppid]) => ppid === app.pid);
    assert.equal(children.length, 1);
    process.kill(children[0][0], "SIGKILL");
    while (true) {
      const n = await reader.read();
      if (n.done) break;
      text += new TextDecoder().decode(n.value);
    }
    assert.equal((text.match(/event: done/g) || []).length, 1);
    const before = await (await app.request(`/api/chats/${c.id}`)).json();
    assert.equal(before.messages.at(-1).status, "error");
    assert.ok(before.messages.at(-1).content.length);
    const requests = app.mock.requests.length;
    await app.stop();
    await app.start();
    const after = await (await app.request(`/api/chats/${c.id}`)).json();
    assert.deepEqual(after.messages, before.messages);
    assert.equal(app.mock.requests.length, requests);
    await (await app.send(c.id, "new user request")).text();
    assert.equal(app.mock.requests.length, requests + 1);
  } finally {
    await app.close();
  }
});

test("stop racing normal completion yields one stable terminal state", async () => {
  const app = await agentApp();
  try {
    for (let i = 0; i < 3; i++) {
      const c = await app.chat();
      const response = await app.send(c.id, "normal");
      await new Promise((r) => setTimeout(r, 250 + i * 40));
      await app.request(`/api/chats/${c.id}/stop`, { method: "POST" });
      const text = await response.text();
      assert.equal((text.match(/event: done/g) || []).length, 1);
      const before = await (await app.request(`/api/chats/${c.id}`)).json();
      assert.ok(
        ["complete", "interrupted"].includes(before.messages.at(-1).status),
      );
      assert.equal(before.generating, false);
      await app.request(`/api/chats/${c.id}/stop`, { method: "POST" });
      assert.deepEqual(
        (await (await app.request(`/api/chats/${c.id}`)).json()).messages,
        before.messages,
      );
    }
  } finally {
    await app.close();
  }
});

test("response safety limit fails without retries and next run recovers", async () => {
  const mock = await mockMlx();
  const c = new AgentClient({ env: { MLX_BASE_URL: mock.url } });
  try {
    await assert.rejects(
      async () => {
        for await (const e of c.run({
          model: "test/coding-model",
          context: [{ role: "user", content: "OUTPUT_LIMIT" }],
        })) {
        }
      },
      (e) => e.code === "output_limit",
    );
    assert.equal(mock.requests.length, 1);
    assert.equal(c.active, false);
    let complete = false;
    for await (const e of c.run({
      model: "test/coding-model",
      context: [{ role: "user", content: "normal" }],
    }))
      if (e.type === "done") complete = true;
    assert.ok(complete);
  } finally {
    await c.close();
    mock.server.closeAllConnections();
    await new Promise((r) => mock.server.close(r));
  }
});
