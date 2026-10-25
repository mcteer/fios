import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import { mockMlx } from "./mock-mlx.js";

export async function agentApp({ python, database, directory } = {}) {
  const mock = await mockMlx();
  const dir = directory || mkdtempSync(join(tmpdir(), "fios-agent-"));
  let child,
    origin,
    cookie = "",
    output = "";
  const password = "isolated-test-password";
  async function start() {
    child = spawn(process.execPath, ["server/index.js"], {
      env: {
        ...process.env,
        PORT: "0",
        HOST: "127.0.0.1",
        DB_PATH: database || join(dir, "test.sqlite"),
        MLX_BASE_URL: mock.url,
        MLX_API_KEY: "isolated-mock-key",
        SESSION_SECRET: "isolated-test-secret-".repeat(3),
        FIOS_PASSWORD: password,
        ...(python ? { FIOS_AGENT_PYTHON: python } : {}),
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    output = "";
    child.stdout.on("data", (b) => {
      output += b;
    });
    child.stderr.on("data", (b) => {
      output += b;
    });
    for (let i = 0; i < 150; i++) {
      const match = output.match(/Fios listening on port (\d+)/);
      if (match) {
        origin = `http://127.0.0.1:${match[1]}`;
        break;
      }
      if (child.exitCode !== null)
        throw new Error("Test server exited before ready");
      await new Promise((r) => setTimeout(r, 30));
    }
    if (!origin) throw new Error("Test app not ready");
    const login = await fetch(origin + "/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });
    cookie = login.headers.get("set-cookie").split(";")[0];
  }
  async function stop() {
    if (child?.exitCode === null) {
      const exit = once(child, "exit");
      child.kill("SIGTERM");
      await exit;
    }
    origin = null;
  }
  const request = (path, options = {}) =>
    fetch(origin + path, {
      ...options,
      headers: { Cookie: cookie, Origin: origin, ...options.headers },
    });
  const chat = async () =>
    (await request("/api/chats", { method: "POST" })).json();
  const send = (id, content, model = "test/coding-model", files = []) => {
    const form = new FormData();
    form.set("content", content);
    form.set("model", model);
    for (const [name, data, type = "text/plain"] of files)
      form.append("files", new Blob([data], { type }), name);
    return request(`/api/chats/${id}/messages`, { method: "POST", body: form });
  };
  await start();
  return {
    mock,
    dir,
    request,
    chat,
    send,
    start,
    stop,
    get pid() {
      return child?.pid;
    },
    get logs() {
      return output;
    },
    get origin() {
      return origin;
    },
    async close() {
      await stop();
      mock.server.closeAllConnections();
      await new Promise((r) => mock.server.close(r));
      if (!directory) rmSync(dir, { recursive: true, force: true });
    },
  };
}
