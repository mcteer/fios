import express from "express";
import multer from "multer";
import { rateLimit } from "express-rate-limit";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { openStore } from "./store.js";
import { equal, signSession, validSession, buildContext } from "./lib.js";
import { parseAttachment } from "./attachments.js";
import { AgentClient } from "../src/agent/client.js";
import { discover } from "../src/agent/availability.js";
import {initialManifest,validateManifest} from '../src/agent/web-protocol.js';

const agent = new AgentClient();
const agentError = (error) => {
  const messages = {
    agent_unavailable:
      "Agent unavailable. Check the installed Python runtime and agent package.",
    agent_protocol_error: "Agent communication failed. Try a new request.",
    model_unavailable: "The selected model or its serving host is unavailable or unverified. Refresh model availability.",
    upstream_http: `MLX-Serve returned HTTP ${error.upstreamStatus || 502}.`,
    upstream_timeout: "MLX-Serve timed out. Partial output was saved.",
    upstream_unavailable:
      "Cannot reach MLX-Serve. Check that the gateway is running.",
    incomplete_stream:
      "MLX-Serve closed the stream before completion. Partial output was saved.",
    unsupported_output:
      "The model returned unsupported output. No tools were executed.",
    output_limit: "Response exceeded the output safety limit.",
    invalid_request: "The agent rejected the conversation context.",
  };
  return (
    messages[error.code] || "Agent generation failed. Partial output was saved."
  );
};

const secret = process.env.SESSION_SECRET;
const password = process.env.FIOS_PASSWORD;
if (!secret || secret.length < 32 || !password || password.length < 12)
  throw new Error(
    "Run scripts/setup.sh: SESSION_SECRET (32+ chars) and FIOS_PASSWORD (12+ chars) are required.",
  );
const base = (
  process.env.MLX_BASE_URL || "http://host.docker.internal:11234/v1"
).replace(/\/$/, "");
const store = openStore(process.env.DB_PATH || "./data/fios.sqlite");
const app = express();
const active = new Map();
app.disable("x-powered-by");
app.use((req, res, next) => {
  res.set({
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy":
      "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; font-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'",
  });
  if (req.path.startsWith("/api/")) res.set("Cache-Control", "no-store");
  if (!["GET", "HEAD", "OPTIONS"].includes(req.method)) {
    const origin = req.get("origin");
    if (
      req.get("sec-fetch-site") === "cross-site" ||
      (origin && origin !== `${req.protocol}://${req.get("host")}`)
    )
      return res
        .status(403)
        .json({ error: "Cross-origin requests are not allowed." });
  }
  next();
});
app.use(express.json({ limit: "128kb" }));
app.get("/health", (req, res) => res.json({ status: "ok" }));
const cookieName = "fios_session";
const cookieOptions = {
  httpOnly: true,
  sameSite: "strict",
  secure: process.env.COOKIE_SECURE === "true",
  path: "/",
  maxAge: 7 * 86400000,
};
const token = (req) =>
  req.headers.cookie
    ?.split(";")
    .map((x) => x.trim())
    .find((x) => x.startsWith(cookieName + "="))
    ?.slice(cookieName.length + 1);
const authenticated = (req) => validSession(token(req), secret);
app.get("/api/session", (req, res) =>
  res.json({ authenticated: authenticated(req) }),
);
app.post(
  "/api/login",
  rateLimit({
    windowMs: 15 * 60000,
    limit: 15,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    handler: (req, res) =>
      res
        .status(429)
        .json({ error: "Too many attempts. Try again in 15 minutes." }),
  }),
  (req, res) => {
    if (!equal(req.body?.password, password))
      return res
        .status(401)
        .json({ error: "That access password is not correct." });
    res
      .cookie(cookieName, signSession(secret), cookieOptions)
      .json({ ok: true });
  },
);
app.use("/api", (req, res, next) =>
  authenticated(req)
    ? next()
    : res.status(401).json({ error: "Sign in to continue." }),
);
app.post("/api/logout", (req, res) =>
  res.clearCookie(cookieName, { path: "/" }).json({ ok: true }),
);
let cachedModels = [];
async function modelCatalog(signal) {
  const result = await discover({base, signal});
  const current = new Set(result.models.map(m => m.id));
  const gatewayUp = result.hosts[0].status === "available";
  const removed = cachedModels.filter(m => !current.has(m.id)).map(m => ({...m,
    availability: "unavailable", reason: gatewayUp ? "not_advertised" : "gateway_unavailable"}));
  // Keep a bounded recent selection history, never stale ready observations.
  result.models = [...result.models, ...removed].slice(0, 512);
  cachedModels = result.models;
  return result;
}
async function models(signal) { return (await modelCatalog(signal)).models; }
app.get("/api/models", async (req, res) => res.json(await modelCatalog()));
app.get("/api/chats", (req, res) => res.json(store.list()));
app.post("/api/chats", (req, res) => res.status(201).json(store.create("")));
app.get("/api/chats/:id", (req, res) => {
  const chat = store.detail(req.params.id);
  if (!chat) return res.status(404).json({ error: "Conversation not found." });
  res.json({ ...chat, generating: active.has(chat.id) });
});
app.delete("/api/chats/:id", (req, res) => {
  if (active.has(req.params.id))
    return res
      .status(409)
      .json({ error: "Stop generation before deleting this chat." });
  if (!store.get(req.params.id))
    return res.status(404).json({ error: "Conversation not found." });
  store.remove(req.params.id);
  res.status(204).end();
});
app.post("/api/chats/:id/stop", (req, res) => {
  active.get(req.params.id)?.abort();
  res.json({ ok: true });
});
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024,
    files: 5,
    fields: 2,
    fieldSize: 100000,
    parts: 7,
  },
}).array("files", 5);
app.post(
  "/api/chats/:id/messages",
  (req, res, next) => {
    if (!store.get(req.params.id))
      return res.status(404).json({ error: "Conversation not found." });
    if (active.size)
      return res.status(409).json({
        error:
          "A response is already generating. Stop it before starting another.",
      });
    const controller = new AbortController();
    active.set(req.params.id, controller);
    res.on("close", () => {
      if (!res.writableEnded) controller.abort();
    });
    // Reserve generation slot before upload/parser work to prevent races.
    req.generation = controller;
    upload(req, res, (err) => {
      if (err) {
        active.delete(req.params.id);
        next(err);
      } else next();
    });
  },
  async (req, res, next) => {
    const id = req.params.id,
      controller = req.generation;
    let assistant,
      content = "",
      reasoning = "",
      status = "complete",
      errorMessage,
      heartbeat;
    const emit = (event, data) => {
      if (!res.destroyed)
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    try {
      const text = String(req.body?.content || "").trim();
      const modelId = String(req.body?.model || "");
      if (text.length > 100000)
        throw Object.assign(new Error("Message exceeds 100,000 characters."), {
          status: 413,
        });
      if (!text && !req.files?.length)
        throw Object.assign(new Error("Write a message or attach a file."), {
          status: 400,
        });
      if (
        (req.files || []).reduce((sum, f) => sum + f.size, 0) >
        20 * 1024 * 1024
      )
        throw Object.assign(
          new Error("Attachments must total 20 MiB or less."),
          { status: 413 },
        );
      const files = await Promise.all((req.files || []).map(parseAttachment));
      const model = (await models(controller.signal)).find((m) => m.id === modelId);
      if (model && model.availability !== "available")
        throw Object.assign(new Error("The selected model or its serving host is unavailable or unverified. Refresh model availability."), {status: 503});
      if (!model)
        throw Object.assign(
          new Error("Choose a chat model currently advertised by MLX-Serve."),
          { status: 400 },
        );
      const oldFiles = store.attachments(id);
      if (
        [...files, ...oldFiles].some((f) => f.kind === "image") &&
        !model.capabilities.includes("vision")
      )
        throw Object.assign(
          new Error(
            "This conversation contains images. Choose a vision-capable model.",
          ),
          { status: 400 },
        );
      const history = store.messages(id);
      const pending = {
        id: "pending",
        role: "user",
        content: text || "Please use the attached files as context.",
      };
      const context = buildContext(
        [...history, pending],
        [...oldFiles, ...files.map((f) => ({ ...f, message_id: pending.id }))],
      );
      controller.signal.throwIfAborted();
      try {
        await agent.ready({ signal: controller.signal });
      } catch {
        throw Object.assign(
          new Error(
            "Agent unavailable. Check the installed Python runtime and agent package.",
          ),
          { status: 503 },
        );
      }
      controller.signal.throwIfAborted();
      const previous=[...history].reverse().find(m=>m.role==='user');
      const provenance=(value)=>typeof value==='string'&&value.length<=2000?value:null;
      const search_input={current_text:provenance(text),current_has_attachments:files.length>0,
        previous_text:provenance(previous?.content??null),previous_has_attachments:oldFiles.some(f=>f.message_id===previous?.id),
        current_elided:text.length>2000,previous_elided:(previous?.content?.length??0)>2000};
      agent.validate({ model: modelId, context, search_input });
      store.db.exec("BEGIN");
      let user;
      try {
        user = store.add(id, "user", pending.content);
        files.forEach((f) => store.file(user.id, f));
        assistant = store.add(id, "assistant", "", "streaming", modelId);
        store.web(assistant.id,initialManifest());
        assistant.web=initialManifest();
        const title = history.length
          ? null
          : (text || files[0]?.name || "New conversation")
              .replace(/\s+/g, " ")
              .slice(0, 70);
        store.touch(id, modelId, title);
        store.db.exec("COMMIT");
      } catch (error) {
        store.db.exec("ROLLBACK");
        throw error;
      }
      res.status(200).set({
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-Accel-Buffering": "no",
      });
      res.flushHeaders();
      emit("meta", {
        user: { ...user, attachments: files.map(({ data, text, ...f }) => f) },
        assistant,
        chat: store.get(id),
      });
      heartbeat = setInterval(() => {
        if (!res.destroyed) res.write(": keepalive\n\n");
      }, 15000);
      let completed = false, pendingStatus=null, statusCount=0, sourceCount=0, reset=false,
        lastSave = Date.now();
      for await (const event of agent.run(
        { model: modelId, context, search_input },
        { signal: controller.signal },
      )) {
        if(pendingStatus && event.type!=='search_sources') throw Object.assign(new Error('Missing source manifest.'),{code:'agent_protocol_error'});
        if(event.type==='search_status') {
          if(++statusCount>16) throw Object.assign(new Error('Metadata limit.'),{code:'agent_protocol_error'});
          const state=event.status;
          if(['retrieved','partial','snippets_only'].includes(state.outcome)) pendingStatus=state;
          else {
            const web={...initialManifest(),...state};
            store.web(assistant.id,web);
            emit('search',state);
          }
        } else if(event.type==='search_sources') {
          if(++sourceCount>2) throw Object.assign(new Error('Metadata limit.'),{code:'agent_protocol_error'});
          const web=validateManifest(event.manifest);
          if(sourceCount===1 && (!pendingStatus||Object.keys(pendingStatus).some(k=>pendingStatus[k]!==web[k]))) throw Object.assign(new Error('Source status mismatch.'),{code:'agent_protocol_error'});
          store.web(assistant.id,web);
          if(pendingStatus) emit('search',pendingStatus);
          pendingStatus=null;
          emit('sources',web);
        } else if(event.type==='answer_reset') {
          if(reset) throw Object.assign(new Error('Duplicate answer reset.'),{code:'agent_protocol_error'});
          reset=true; content=''; reasoning='';
          store.update(assistant.id,'','streaming');
          emit('answer_reset',{reason:'tool_requested'});
        } else if (event.type === "delta") {
          content += event.content;
          emit("delta", { content: event.content });
        } else if (event.type === "reasoning") {
          reasoning += event.content;
          emit("reasoning", { content: event.content });
        } else if (event.type === "done") {
          completed = true;
          if (event.status === "interrupted") {
            status = "interrupted";
            emit("error", { error: "Response stopped or timed out.", status });
          }
        }
        if (content.length + reasoning.length > 500000) {
          controller.abort(
            new Error("Response exceeded the output safety limit."),
          );
          throw Object.assign(new Error("Output limit."), {
            code: "output_limit",
          });
        }
        if (Date.now() - lastSave > 1000) {
          store.update(assistant.id, content, "streaming");
          lastSave = Date.now();
        }
      }
      if(pendingStatus) throw Object.assign(new Error('Missing source manifest.'),{code:'agent_protocol_error'});
      if (!completed)
        throw Object.assign(new Error("Incomplete agent stream."), {
          code: "incomplete_stream",
        });
    } catch (error) {
      if (!assistant) {
        active.delete(id);
        return next(error);
      }
      status = controller.signal.aborted ? "interrupted" : "error";
      errorMessage =
        controller.signal.reason?.message ||
        (status === "interrupted" ? "Response stopped." : agentError(error));
      emit("error", { error: errorMessage, status });
    } finally {
      clearInterval(heartbeat);
      if (assistant) {
        const web=store.readWeb(assistant.id);
        if(web&&web.phase!=='finished') {
          const outcome=status==='interrupted'?'cancelled':'error';
          store.web(assistant.id,{...web,phase:'finished',outcome,reason:outcome==='cancelled'?'run_cancelled':'tool_error'});
        }
        store.update(assistant.id, content, status);
        store.touch(id, store.get(id)?.model || "");
        emit("done", { id: assistant.id, status });
        if (!res.destroyed) res.end();
      }
      active.delete(id);
    }
  },
);
app.use("/api", (req, res) =>
  res.status(404).json({ error: "API endpoint not found." }),
);
const dist = fileURLToPath(new URL("../dist", import.meta.url));
app.use(express.static(dist, { index: false }));
app.get("/{*path}", (req, res) => res.sendFile(resolve(dist, "index.html")));
app.use((error, req, res, next) => {
  if (res.headersSent) return res.end();
  let status = error.status || 500,
    message = error.message;
  if (error instanceof multer.MulterError) {
    status = 400;
    message = "Upload limit exceeded. Use up to 5 files, at most 10 MiB each.";
  }
  if (
    error.name === "TimeoutError" ||
    error.cause?.code === "ECONNREFUSED" ||
    message === "fetch failed"
  ) {
    status = 502;
    message =
      "Cannot reach MLX-Serve. Check that it is running on this host at port 11234.";
  }
  res
    .status(status)
    .json({ error: message || "An unexpected error occurred." });
});
const server = app.listen(
  Number(process.env.PORT || 3000),
  process.env.HOST || "0.0.0.0",
  () => console.log("Fios listening on port " + server.address().port),
);
process.on("SIGTERM", () => {
  for (const c of active.values()) c.abort();
  const cleanup = agent.close();
  server.close(async () => {
    await cleanup;
    store.db.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 8000).unref();
});
