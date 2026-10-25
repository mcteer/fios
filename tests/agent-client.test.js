import test from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { AgentClient, childEnvironment } from "../src/agent/client.js";
import {
  FrameDecoder,
  ProtocolError,
  encodeFrame,
  parseCommand,
  parseEvent,
} from "../src/agent/protocol.js";

const python =
  process.env.FIOS_AGENT_PYTHON ||
  fileURLToPath(new URL("../.venv/bin/python", import.meta.url));
const fixture = fileURLToPath(
  new URL("fixtures/agent-worker.py", import.meta.url),
);
const make = (mode = "normal", options = {}) =>
  new AgentClient({
    python,
    args: ["-I", "-B", fixture, mode],
    startupMs: 500,
    ...options,
  });
const input = () => ({
  model: "mlx/coding-model@studio-a",
  context: [{ role: "user", content: "Hi 🧵" }],
});
const collect = async (events) => {
  const out = [];
  for await (const e of events) out.push(e);
  return out;
};

test("private protocol is strict, bounded, and preserves UTF8 across chunks", () => {
  const run = { v: 2, type: "run", run_id: randomUUID(), ...input() };
  assert.equal(parseCommand(run).model, run.model);
  for (const patch of [
    { v: true },
    { v: 1 },
    { key: "secret" },
    { run_id: "bad" },
    { model: "é".repeat(513) },
    { context: [] },
  ])
    assert.throws(() => parseCommand({ ...run, ...patch }), ProtocolError);
  const frame = encodeFrame(run);
  const decoder = new FrameDecoder(32 * 1024 * 1024);
  const values = [];
  for (const byte of frame) values.push(...decoder.feed(Buffer.from([byte])));
  decoder.finish();
  assert.deepEqual(values, [run]);
  assert.throws(
    () => [...new FrameDecoder(4).feed(Buffer.from("12345"))],
    ProtocolError,
  );
  assert.throws(
    () => [...new FrameDecoder(8).feed(Buffer.from([255, 10]))],
    ProtocolError,
  );
  assert.throws(
    () => parseEvent({ v: 2, type: "ready", extra: true }),
    ProtocolError,
  );
  assert.throws(
    () =>
      parseEvent({
        v: 2,
        type: "error",
        run_id: run.run_id,
        code: "sensitive",
      }),
    ProtocolError,
  );
  assert.throws(
    () =>
      parseEvent({
        v: 2,
        type: "delta",
        run_id: run.run_id,
        content: "a".repeat(32769),
      }),
    ProtocolError,
  );
  assert.throws(
    () => [...new FrameDecoder(100).feed(Buffer.from('{"v":1,"v":2}\n'))],
    ProtocolError,
  );
});

test("supervisor streams one correlated run, excludes ambient secrets, then shuts down/reaps", async () => {
  const env = childEnvironment({
    PATH: "/bin",
    HOME: "/tmp",
    MLX_BASE_URL: "http://localhost:11234/v1",
    MLX_API_KEY: "test-only",
    FIOS_PASSWORD: "do-not-inherit",
    SESSION_SECRET: "do-not-inherit",
    OPENAI_API_KEY: "do-not-inherit",
    HTTPS_PROXY: "do-not-inherit",
    PYTHONPATH: "do-not-inherit",
  });
  assert.equal(env.MLX_API_KEY, "test-only");
  for (const key of [
    "FIOS_PASSWORD",
    "SESSION_SECRET",
    "OPENAI_API_KEY",
    "HTTPS_PROXY",
    "PYTHONPATH",
  ])
    assert.equal(env[key], undefined);
  const client = make();
  try {
    await client.ready();
    const events = await collect(client.run(input()));
    assert.deepEqual(
      events.map((e) => e.type),
      ["started", "delta", "done"],
    );
    assert.equal(events[1].content, "hello 🧵");
    assert.equal(new Set(events.map((e) => e.run_id)).size, 1);
    assert.equal(client.active, false);
  } finally {
    await client.close();
  }
  assert.equal(client.pid, null);
});

test("startup failures fail closed with content-free errors and bounded cleanup", async () => {
  for (const mode of [
    "startup_exit",
    "hang_start",
    "wrong_version",
    "oversized",
  ]) {
    const client = make(mode, { startupMs: 100 });
    try {
      await assert.rejects(
        client.ready(),
        /Agent (unavailable|protocol error)/,
      );
    } finally {
      await client.close();
    }
    assert.equal(client.pid, null);
  }
});

test("worker exits/mismatched IDs cannot complete a request or replay it", async () => {
  for (const mode of ["exit_run", "mismatch"]) {
    const client = make(mode);
    try {
      await assert.rejects(
        collect(client.run(input())),
        /Agent (unavailable|protocol error)/,
      );
      assert.equal(client.active, false);
    } finally {
      await client.close();
    }
  }
});

test("no model submission for pre-aborted signal; global active slot rejects another run", async () => {
  const client = make("wait_cancel");
  try {
    const aborted = new AbortController();
    aborted.abort();
    await assert.rejects(
      collect(client.run(input(), { signal: aborted.signal })),
      /stopped/,
    );
    assert.equal(client.pid, null);
    const controller = new AbortController();
    const iterator = client.run(input(), { signal: controller.signal });
    assert.equal((await iterator.next()).value.type, "started");
    await assert.rejects(collect(client.run(input())), /already active/);
    controller.abort();
    const rest = await collect(iterator);
    assert.deepEqual(
      rest.map((x) => x.status),
      ["interrupted"],
    );
    assert.equal(client.active, false);
  } finally {
    await client.close();
  }
});

test("consumer backpressure does not deadlock cancellation or shutdown", async () => {
  const client = make();
  const iterator = client.run(input());
  await iterator.next();
  await client.close();
  await iterator.return();
  assert.equal(client.active, false);
  assert.equal(client.pid, null);
});
