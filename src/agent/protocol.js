import {validateSearchInput,validateSearchStatus,validateManifest} from './web-protocol.js';
export const REQUEST_LIMIT = 32 * 1024 * 1024;
export const EVENT_LIMIT = 1024 * 1024;
export const TEXT_CHUNK_UNITS = 32 * 1024;
export const ERROR_CODES = new Set([
  "busy",
  "invalid_request",
  "upstream_unavailable",
  "model_unavailable",
  "upstream_http",
  "upstream_timeout",
  "incomplete_stream",
  "invalid_stream",
  "unsupported_output",
  "output_limit",
  "internal_error",
  "search_tool_protocol", "search_budget_exceeded", "agent_context_limit",
]);
export class ProtocolError extends Error {
  constructor() {
    super("Agent protocol error.");
    this.code = "agent_protocol_error";
  }
}
const fail = () => {
  throw new ProtocolError();
};
const record = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
function fields(v, required, optional = []) {
  if (
    !record(v) ||
    required.some((k) => !Object.hasOwn(v, k)) ||
    Object.keys(v).some((k) => !required.includes(k) && !optional.includes(k))
  )
    fail();
}
function correlated(v) {
  if (
    typeof v.run_id !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      v.run_id,
    )
  )
    fail();
}
function text(v) {
  if (typeof v !== "string" || !v.isWellFormed()) fail();
}
function context(items) {
  if (!Array.isArray(items) || !items.length || items.at(-1)?.role !== "user")
    fail();
  for (const item of items) {
    fields(item, ["role", "content"]);
    if (!["user", "assistant"].includes(item.role)) fail();
    if (typeof item.content === "string") {
      text(item.content);
      if (item.role === "assistant" && !item.content) fail();
    } else {
      if (
        item.role !== "user" ||
        !Array.isArray(item.content) ||
        !item.content.length
      )
        fail();
      for (const part of item.content) {
        if (part?.type === "text") {
          fields(part, ["type", "text"]);
          text(part.text);
        } else if (part?.type === "image_url") {
          fields(part, ["type", "image_url"]);
          fields(part.image_url, ["url"]);
          text(part.image_url.url);
        } else fail();
      }
    }
  }
}
export function parseCommand(v) {
  if (v?.v !== 2) fail();
  if (v.type === "shutdown") fields(v, ["v", "type"]);
  else if (v.type === "cancel") {
    fields(v, ["v", "type", "run_id"]);
    correlated(v);
  } else if (v.type === "run") {
    fields(v, ["v", "type", "run_id", "model", "context"], ['search_input']);
    if (Object.hasOwn(v,'search_input')) {
      try {validateSearchInput(v.search_input);} catch {fail();}
    }
    correlated(v);
    text(v.model);
    if (!v.model || Buffer.byteLength(v.model) > 1024) fail();
    context(v.context);
  } else fail();
  return v;
}
export function parseEvent(v) {
  if (v?.v !== 2) fail();
  if (v.type === "ready") fields(v, ["v", "type"]);
  else {
    correlated(v);
    const base = ["v", "type", "run_id"];
    if (["started", "activity"].includes(v.type)) fields(v, base);
    else if (["delta", "reasoning"].includes(v.type)) {
      fields(v, [...base, "content"]);
      text(v.content);
      if (v.content.length > TEXT_CHUNK_UNITS) fail();
    } else if (v.type === 'search_status') {
      fields(v,[...base,'status']);
      try {validateSearchStatus(v.status);} catch {fail();}
    } else if (v.type === 'search_sources') {
      fields(v,[...base,'manifest']);
      try {validateManifest(v.manifest);} catch {fail();}
    } else if (v.type === 'answer_reset') {
      fields(v,[...base,'reason']);
      if (v.reason!=='tool_requested') fail();
    } else if (v.type === "done") {
      fields(v, [...base, "status"]);
      if (!["complete", "interrupted"].includes(v.status)) fail();
    } else if (v.type === "error") {
      fields(v, [...base, "code"], ["upstream_status"]);
      if (!ERROR_CODES.has(v.code)) fail();
      if (
        Object.hasOwn(v, "upstream_status") &&
        (!Number.isInteger(v.upstream_status) ||
          v.upstream_status < 400 ||
          v.upstream_status > 599)
      )
        fail();
    } else fail();
  }
  return v;
}
// JSON.parse validates syntax first; this second structural pass rejects duplicate keys.
function uniqueKeys(source) {
  let i = 0;
  const ws = () => {
    while (/\s/.test(source[i] || "x")) i++;
  };
  function string() {
    const start = i++;
    while (source[i] !== '"') {
      if (source[i++] === "\\") i++;
    }
    return JSON.parse(source.slice(start, ++i));
  }
  function value(depth = 0) {
    if (depth > 32) fail();
    ws();
    if (source[i] === "{") {
      i++;
      ws();
      const keys = new Set();
      while (source[i] !== "}") {
        const key = string();
        if (keys.has(key)) fail();
        keys.add(key);
        ws();
        i++;
        value(depth + 1);
        ws();
        if (source[i] !== ",") break;
        i++;
        ws();
      }
      i++;
    } else if (source[i] === "[") {
      i++;
      ws();
      while (source[i] !== "]") {
        value(depth + 1);
        ws();
        if (source[i] !== ",") break;
        i++;
      }
      i++;
    } else if (source[i] === '"') string();
    else {
      while (i < source.length && !/[\s,\]}]/.test(source[i])) i++;
    }
  }
  value();
}
export class FrameDecoder {
  constructor(limit) {
    this.limit = limit;
    this.buffer = Buffer.alloc(Math.min(limit + 1, 4096));
    this.size = 0;
  }
  *feed(bytes) {
    let offset = 0;
    while (offset < bytes.length) {
      const end = bytes.indexOf(10, offset),
        boundary = end < 0 ? bytes.length : end;
      const part = bytes.subarray(offset, boundary);
      if (this.size + part.length > this.limit + 1) fail();
      // Geometrically grow one byte buffer: tiny input chunks cannot accumulate
      // millions of Buffer objects, and incoming buffers are never retained.
      if (this.size + part.length > this.buffer.length) {
        const capacity = Math.min(
          this.limit + 1,
          Math.max(this.size + part.length, this.buffer.length * 2),
        );
        const next = Buffer.alloc(capacity);
        this.buffer.copy(next, 0, 0, this.size);
        this.buffer = next;
      }
      part.copy(this.buffer, this.size);
      this.size += part.length;
      if (end < 0) {
        if (this.size > this.limit && part.at(-1) !== 13) fail();
        return;
      }
      let raw = this.buffer.subarray(0, this.size);
      this.size = 0;
      if (raw.at(-1) === 13) raw = raw.subarray(0, -1);
      if (!raw.length || raw.length > this.limit) fail();
      try {
        const source = new TextDecoder("utf-8", { fatal: true }).decode(raw);
        const obj = JSON.parse(source);
        if (!record(obj)) fail();
        uniqueKeys(source);
        yield obj;
      } catch {
        fail();
      }
      offset = end + 1;
    }
  }
  finish() {
    if (this.size) fail();
  }
}
export function encodeFrame(value, limit = REQUEST_LIMIT) {
  let raw;
  try {
    raw = Buffer.from(JSON.stringify(value));
  } catch {
    fail();
  }
  if (raw.length > limit) fail();
  return Buffer.concat([raw, Buffer.from("\n")]);
}
