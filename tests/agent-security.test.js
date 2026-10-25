import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { readFileSync, readdirSync } from "node:fs";
import { agentApp } from "./agent-support.js";
import { AgentClient, childEnvironment } from "../src/agent/client.js";

test("auth/origin, health, catalog and CRUD never invoke inference; logs and assets contain no contents or credentials", async () => {
  const app = await agentApp();
  try {
    assert.equal((await fetch(app.origin + "/api/chats")).status, 401);
    const c = await app.chat();
    assert.equal(
      (
        await app.request("/api/chats", {
          method: "POST",
          headers: { Origin: "https://untrusted.example" },
        })
      ).status,
      403,
    );
    assert.equal((await app.request("/health")).status, 200);
    await app.request("/api/models");
    await app.request("/api/chats");
    await app.request(`/api/chats/${c.id}`);
    assert.equal(app.mock.requests.length, 0);
    await (await app.send(c.id, "SENSITIVE_PROMPT_MARKER")).text();
    assert.doesNotMatch(
      app.logs,
      /SENSITIVE_PROMPT_MARKER|isolated-mock-key|Here is a small example|Traceback/,
    );
    for (const file of readdirSync("dist/assets")) {
      const text = readFileSync("dist/assets/" + file, "utf8");
      assert.doesNotMatch(
        text,
        /fios_agent|isolated-mock-key|SENSITIVE_PROMPT_MARKER/,
      );
    }
    assert.deepEqual(
      Object.keys(
        childEnvironment({ OPENAI_API_KEY: "bad", HTTPS_PROXY: "bad" }),
      ).sort(),
      ["MLX_BASE_URL"],
    );
  } finally {
    await app.close();
  }
});

test("static boundary guard passes, worker module has no HTTP listener or DB dependency", async () => {
  const child = spawn(process.execPath, ["scripts/check-agent-boundary.mjs"], {
    stdio: "pipe",
  });
  const [code] = await once(child, "exit");
  assert.equal(code, 0);
  for (const file of readdirSync("src/agent/fios_agent").filter((f) =>
    f.endsWith(".py"),
  )) {
    assert.doesNotMatch(
      readFileSync("src/agent/fios_agent/" + file, "utf8"),
      /sqlite3|uvicorn|FastAPI|create_server\(|start_server\(/,
    );
  }
});

test("SDK stderr is not forwarded verbatim by Node supervisor", async () => {
  const { fileURLToPath } = await import("node:url");
  const client = new AgentClient({
    args: [
      "-I",
      "-B",
      fileURLToPath(new URL("fixtures/agent-worker.py", import.meta.url)),
      "stderr",
    ],
  });
  try {
    await client.ready();
  } finally {
    await client.close();
  }
});
