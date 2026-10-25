import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mockMlx } from "./mock-mlx.js";

test("authenticated API: discovery, attachments, streaming, errors, stop, persistence and deletion", async () => {
  const mock = await mockMlx(),
    dir = mkdtempSync(join(tmpdir(), "fios-test-"));
  const port = 3337,
    origin = `http://127.0.0.1:${port}`,
    password = "test-workspace-password";
  let child,
    cookie = "";
  const start = async () => {
    child = spawn(process.execPath, ["server/index.js"], {
      env: {
        ...process.env,
        PORT: String(port),
        HOST: "127.0.0.1",
        DB_PATH: join(dir, "test.sqlite"),
        MLX_BASE_URL: mock.url,
        FIOS_PASSWORD: password,
        SESSION_SECRET: "test-secret-".repeat(5),
      },
      stdio: "pipe",
    });
    let output = "";
    child.stderr.on("data", (x) => (output += x));
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error(output);
      try {
        if ((await fetch(origin + "/health")).ok) return;
      } catch {}
      await new Promise((r) => setTimeout(r, 40));
    }
    throw new Error("Server did not start " + output);
  };
  const stop = async () => {
    if (child && child.exitCode === null) {
      child.kill("SIGTERM");
      await new Promise((r) => child.once("exit", r));
    }
  };
  const request = (path, options = {}) =>
    fetch(origin + "/api" + path, {
      ...options,
      headers: { Cookie: cookie, Origin: origin, ...options.headers },
    });
  const form = (content, files = []) => {
    const f = new FormData();
    f.set("content", content);
    f.set("model", "test/coding-model");
    for (const [name, text] of files)
      f.append("files", new Blob([text], { type: "text/plain" }), name);
    return f;
  };
  try {
    await start();
    assert.equal((await request("/chats")).status, 401);
    assert.equal(
      (
        await request("/login", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ password: "incorrect" }),
        })
      ).status,
      401,
    );
    const login = await request("/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    assert.equal(login.status, 200);
    cookie = login.headers.get("set-cookie").split(";")[0];
    assert.match(login.headers.get("set-cookie"), /HttpOnly/);
    assert.equal(
      (
        await request("/chats", {
          method: "POST",
          headers: { Origin: "https://evil.example" },
        })
      ).status,
      403,
    );
    const catalog = await (await request("/models")).json();
    assert.equal(catalog.models.length, 2);
    const chat = await (await request("/chats", { method: "POST" })).json();
    const bad = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("hello", [["empty.txt", ""]]),
    });
    assert.equal(bad.status, 400);
    const response = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("Review my code", [["sample.js", "const x = 42;"]]),
    });
    assert.equal(response.status, 200);
    const stream = await response.text();
    assert.match(stream, /event: delta/);
    assert.match(stream, /event: done/);
    assert.match(stream, /greeting/);
    assert.match(mock.requests[0].messages.at(-1).content, /const x = 42/);
    let detail = await (await request(`/chats/${chat.id}`)).json();
    assert.equal(detail.messages.length, 2);
    assert.equal(detail.messages[1].status, "complete");
    assert.equal(detail.messages[0].attachments[0].name, "sample.js");
    const second = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("What does it do?"),
    });
    await second.text();
    assert.match(mock.requests[1].messages[1].content, /const x = 42/);
    await stop();
    await start();
    detail = await (await request(`/chats/${chat.id}`)).json();
    assert.equal(detail.messages.length, 4);
    const failed = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("FAIL_UPSTREAM"),
    });
    assert.match(await failed.text(), /HTTP 503/);
    detail = await (await request(`/chats/${chat.id}`)).json();
    assert.equal(detail.messages.at(-1).status, "error");
    const slow = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("SLOW_RESPONSE"),
    });
    assert.equal(
      (await request(`/chats/${chat.id}`, { method: "DELETE" })).status,
      409,
    );
    await request(`/chats/${chat.id}/stop`, { method: "POST" });
    await slow.text();
    detail = await (await request(`/chats/${chat.id}`)).json();
    assert.equal(detail.messages.at(-1).status, "interrupted");
    // A removal immediately invalidates inference even within the old cache window.
    mock.catalog.splice(0, 1);
    const staleSend = await request(`/chats/${chat.id}/messages`, {
      method: "POST",
      body: form("Do not send to a removed model"),
    });
    assert.equal(staleSend.status, 503);
    const updated = await request("/models");
    assert.equal(updated.headers.get("cache-control"), "no-store");
    assert.equal(
      (await updated.json()).models.some((m) => m.id === "test/coding-model" && m.availability === "available"),
      false,
    );
    mock.catalog.push({ id: "test/added-model", capabilities: ["chat"] });
    assert.ok(
      (await (await request("/models")).json()).models.some(
        (m) => m.id === "test/added-model",
      ),
    );
    assert.equal(
      (await request(`/chats/${chat.id}`, { method: "DELETE" })).status,
      204,
    );
    assert.equal((await request(`/chats/${chat.id}`)).status, 404);
    assert.equal((await (await request("/chats")).json()).length, 0);
  } finally {
    await stop();
    mock.server.closeAllConnections();
    await new Promise((r) => mock.server.close(r));
    rmSync(dir, { recursive: true, force: true });
  }
});
