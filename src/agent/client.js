import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { once } from "node:events";
import {
  FrameDecoder,
  EVENT_LIMIT,
  ProtocolError,
  encodeFrame,
  parseCommand,
  parseEvent,
} from "./protocol.js";

const root = fileURLToPath(new URL("../../", import.meta.url));
const unavailable = () =>
  Object.assign(new Error("Agent unavailable."), { code: "agent_unavailable" });
const stopped = () =>
  Object.assign(new Error("Response stopped."), { code: "agent_cancelled" });

export function childEnvironment(env = process.env) {
  const result = {};
  for (const key of [
    "PATH",
    "HOME",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "MLX_BASE_URL",
    "MLX_API_KEY",
    "MLX_PEER_URLS",
    "MLX_READINESS_FILE",
    "FIOS_WEB_SEARCH",
  ])
    if (typeof env[key] === "string") result[key] = env[key];
  result.MLX_BASE_URL ||= "http://host.docker.internal:11234/v1";
  return result;
}

// Single buffered event; producer waits for space. Cancellation unblocks producer.
class Events {
  constructor() {
    this.items = [];
    this.ended = false;
    this.error = null;
    this.wake = null;
    this.space = null;
    this.discard = false;
  }
  async push(value) {
    while (this.items.length && !this.ended && !this.discard)
      await new Promise((r) => {
        this.space = r;
      });
    if (this.ended || (this.discard && value.type !== "done")) return;
    this.items.push(value);
    this.wake?.();
    this.wake = null;
  }
  cancelPending() {
    this.discard = true;
    this.items = [];
    this.space?.();
    this.space = null;
  }
  end(error) {
    this.ended = true;
    this.error = error;
    this.wake?.();
    this.space?.();
  }
  async next() {
    while (!this.items.length && !this.ended)
      await new Promise((r) => {
        this.wake = r;
      });
    if (this.items.length) {
      const value = this.items.shift();
      this.space?.();
      this.space = null;
      return { value, done: false };
    }
    if (this.error) throw this.error;
    return { done: true };
  }
}

export class AgentClient {
  constructor({
    python = process.env.FIOS_AGENT_PYTHON ||
      fileURLToPath(new URL("../../.venv/bin/python", import.meta.url)),
    args = ["-I", "-B", "-m", "fios_agent"],
    env = process.env,
    startupMs = 10000,
    idleMs = 180000,
    termMs = 1000,
    killMs = 1500,
  } = {}) {
    this.options = { python, args, env, startupMs, idleMs, termMs, killMs };
    this.worker = null;
    this.current = null;
    this.starting = null;
    this.closed = false;
  }
  get pid() {
    return this.worker?.child.pid ?? null;
  }
  get active() {
    return this.current !== null;
  }

  async ready({ signal } = {}) {
    if (signal?.aborted) throw stopped();
    if (this.closed) throw unavailable();
    if (this.worker?.ready) return;
    if (!this.starting)
      this.starting = this.startWorker().finally(() => {
        this.starting = null;
      });
    const abort = () => {
      if (this.worker && !this.worker.ready) this.fail(this.worker, stopped());
    };
    signal?.addEventListener("abort", abort, { once: true });
    try {
      await this.starting;
      if (signal?.aborted) throw stopped();
    } finally {
      signal?.removeEventListener("abort", abort);
    }
  }
  async startWorker() {
    const { python, args, env, startupMs } = this.options;
    const child = spawn(python, args, {
      cwd: root,
      env: childEnvironment(env),
      shell: false,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let resolveReady, rejectReady, resolveExit;
    const pending = new Promise((resolve, reject) => {
      resolveReady = resolve;
      rejectReady = reject;
    });
    const worker = {
      child,
      ready: false,
      resolveReady,
      rejectReady,
      exit: new Promise((resolve) => {
        resolveExit = resolve;
      }),
      resolveExit: null,
      failure: null,
    };
    worker.resolveExit = resolveExit;
    this.worker = worker;
    // Raw child stderr is untrusted and may contain exception bodies or prompts.
    child.stderr.resume();
    child.stdin.on("error", () => this.fail(worker, unavailable()));
    child.on("error", () => this.fail(worker, unavailable()));
    child.on("close", () => {
      if (this.worker === worker) this.worker = null;
      worker.resolveExit();
      worker.rejectReady(worker.failure || unavailable());
      const run = this.current;
      if (run?.worker === worker)
        this.finish(
          run,
          run.cancelled ? null : worker.failure || unavailable(),
          run.cancelled ? "interrupted" : null,
        );
    });
    const deadline = setTimeout(
      () => this.fail(worker, unavailable()),
      startupMs,
    );
    this.read(worker).catch(() => this.fail(worker, new ProtocolError()));
    try {
      await pending;
    } catch (error) {
      await worker.exit;
      throw error;
    } finally {
      clearTimeout(deadline);
    }
  }
  async read(worker) {
    const decoder = new FrameDecoder(EVENT_LIMIT);
    for await (const chunk of worker.child.stdout) {
      for (const raw of decoder.feed(chunk)) {
        const event = parseEvent(raw);
        if (!worker.ready) {
          if (event.type !== "ready") throw new ProtocolError();
          worker.ready = true;
          worker.resolveReady();
          continue;
        }
        if (event.type === "ready") throw new ProtocolError();
        const run = this.current;
        if (
          !run ||
          run.worker !== worker ||
          event.run_id !== run.id ||
          run.terminal
        )
          throw new ProtocolError();
        if (event.type === "activity") {
          this.resetIdle(run);
          continue;
        }
        if (event.type === "done" || event.type === "error") {
          if (event.type === "error" && !run.cancelled) {
            const error = Object.assign(new Error("Agent run failed."), {
              code: event.code,
              upstreamStatus: event.upstream_status,
            });
            this.finish(run, error);
          } else
            this.finish(
              run,
              null,
              run.cancelled ? "interrupted" : event.status,
            );
        } else if (!run.cancelled) {
          if (['search_status','search_sources','answer_reset'].includes(event.type)) this.resetIdle(run);
          await run.events.push(event);
        }
      }
    }
    decoder.finish();
  }
  fail(worker, error) {
    worker.failure ||= error;
    worker.ready = false;
    worker.rejectReady(worker.failure);
    // Reap before making another process available; never replay active input.
    worker.child.kill("SIGKILL");
  }
  async write(worker, frame) {
    if (this.worker !== worker || !worker.ready || worker.child.stdin.destroyed)
      throw unavailable();
    const bytes = encodeFrame(frame);
    if (!worker.child.stdin.write(bytes))
      await once(worker.child.stdin, "drain");
  }
  resetIdle(run) {
    clearTimeout(run.idle);
    run.idle = setTimeout(() => this.cancel(run), this.options.idleMs);
  }
  finish(run, error = null, status = null) {
    if (run.terminal) return;
    run.terminal = true;
    if (error)
      console.error(
        JSON.stringify({
          phase: "agent",
          run_id: run.id,
          code: error.code || "agent_unavailable",
          elapsed_ms: Date.now() - run.startedAt,
        }),
      );
    clearTimeout(run.idle);
    clearTimeout(run.term);
    clearTimeout(run.kill);
    run.signal?.removeEventListener("abort", run.abort);
    if (this.current === run) this.current = null;
    if (status) {
      // Terminal frame cannot be held hostage by an abandoned consumer.
      if (run.cancelled) run.events.cancelPending();
      run.events
        .push({ v: 2, type: "done", run_id: run.id, status })
        .then(() => run.events.end());
    } else run.events.end(error || unavailable());
    run.resolveFinished();
  }
  cancel(run) {
    if (run.terminal || run.cancelled) return;
    run.cancelled = true;
    clearTimeout(run.idle);
    run.events.cancelPending();
    this.write(run.worker, { v: 2, type: "cancel", run_id: run.id }).catch(() =>
      this.fail(run.worker, unavailable()),
    );
    run.term = setTimeout(
      () => run.worker.child.kill("SIGTERM"),
      this.options.termMs,
    );
    run.kill = setTimeout(
      () => run.worker.child.kill("SIGKILL"),
      this.options.killMs,
    );
  }
  validate(input, id = randomUUID()) {
    if (
      !input ||
      Object.keys(input).some((key) => !["model", "context", "search_input"].includes(key))
    )
      throw new ProtocolError();
    const frame = parseCommand({
      v: 2,
      type: "run",
      run_id: id,
      model: input.model,
      context: input.context,
      ...(input.search_input ? {search_input:input.search_input} : {}),
    });
    // Check framing bound before spawning, persistence or sending a byte.
    encodeFrame(frame);
    return frame;
  }
  async *run(input, { signal } = {}) {
    if (signal?.aborted) throw stopped();
    if (this.current) throw new Error("Agent run already active.");
    const id = randomUUID();
    const frame = this.validate(input, id);
    let resolveFinished;
    const run = {
      id,
      signal,
      startedAt: Date.now(),
      worker: null,
      events: new Events(),
      terminal: false,
      cancelled: false,
      finished: new Promise((resolve) => {
        resolveFinished = resolve;
      }),
      resolveFinished: null,
    };
    run.resolveFinished = resolveFinished;
    this.current = run;
    try {
      await this.ready({ signal });
      if (signal?.aborted || run.terminal || this.closed) throw stopped();
      run.worker = this.worker;
      run.abort = () => this.cancel(run);
      signal?.addEventListener("abort", run.abort, { once: true });
      await this.write(run.worker, frame);
      this.resetIdle(run);
      while (true) {
        const next = await run.events.next();
        if (next.done) break;
        yield next.value;
      }
    } catch (error) {
      if (!run.terminal) this.finish(run, error);
      throw error;
    } finally {
      if (!run.terminal) {
        this.cancel(run);
        await run.finished;
      }
    }
  }
  async close() {
    this.closed = true;
    const run = this.current;
    if (run?.worker) {
      this.cancel(run);
      await run.finished;
    } else if (run) this.finish(run, unavailable());
    const worker = this.worker;
    if (!worker) return;
    if (worker.ready)
      await this.write(worker, { v: 2, type: "shutdown" }).catch(() => {});
    else worker.child.kill("SIGTERM");
    const term = setTimeout(
      () => worker.child.kill("SIGTERM"),
      this.options.termMs,
    );
    const kill = setTimeout(
      () => worker.child.kill("SIGKILL"),
      this.options.killMs,
    );
    try {
      await worker.exit;
    } finally {
      clearTimeout(term);
      clearTimeout(kill);
    }
  }
}
