// Discovery only. Never follow catalog-provided URLs or issue inference/load requests.
import {openSync, closeSync, fstatSync, readSync, constants} from "node:fs";
import {createHash} from "node:crypto";
const MAX_BYTES = 1024 * 1024;
export const OBSERVATION_MAX_AGE_MS = 5000;
export const endpointHash = url => createHash("sha256").update(endpoint(url)).digest("hex");
function snapshotObservation(path, name, url) {
  let fd;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
    if (!fstatSync(fd).isFile()) throw new Error("snapshot");
    const bytes = Buffer.alloc(MAX_BYTES + 1);
    const size = readSync(fd, bytes, 0, bytes.length, 0);
    if (size > MAX_BYTES) throw new Error("snapshot");
    const value = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(bytes.subarray(0, size)));
    const observation = value.peers?.find(p => p.name === name && p.endpointHash === endpointHash(url));
    const now = Date.now();
    if (value.v !== 1 || !observation || !Number.isSafeInteger(observation.checkedAt) || now - observation.checkedAt > OBSERVATION_MAX_AGE_MS || observation.checkedAt > now + 1000 ||
      !["available", "unavailable", "unknown"].includes(observation.status) ||
      !["ok", "host_down", "unauthorized", "invalid_catalog", "host_unverified"].includes(observation.reason) ||
      (observation.status === "available" && observation.reason !== "ok")) throw new Error("snapshot");
    const models = observation.status === "available" ? catalog({data: observation.models}) : [];
    return {name, status: observation.status, reason: observation.reason, checkedAt: observation.checkedAt, models, modelCount: models.filter(m => !m.lan_peer && !m.id.includes("@")).length};
  } catch { return {name, status: "unknown", reason: "host_unverified", checkedAt: Date.now(), modelCount: 0, models: []}; }
  finally { if (fd !== undefined) closeSync(fd); }
}
export function endpoint(value) {
  if (typeof value !== "string" || /[\s?#]/u.test(value)) throw new Error("Invalid availability configuration.");
  let url;
  try { url = new URL(value); } catch { throw new Error("Invalid availability configuration."); }
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password || !url.pathname.replace(/\/$/, "").endsWith("/v1"))
    throw new Error("Invalid availability configuration.");
  return url.href.replace(/\/$/, "");
}
export function peerConfiguration(value = "{}") {
  let peers;
  try { peers = JSON.parse(value || "{}"); } catch { throw new Error("Invalid availability configuration."); }
  if (!peers || Array.isArray(peers) || typeof peers !== "object" || Object.keys(peers).length > 16)
    throw new Error("Invalid availability configuration.");
  return Object.fromEntries(Object.entries(peers).map(([name, url]) => {
    if (!/^[A-Za-z0-9_.-]{1,128}$/.test(name) || name === "gateway") throw new Error("Invalid availability configuration.");
    return [name, endpoint(url)];
  }));
}
function catalog(payload) {
  if (!payload || !Array.isArray(payload.data) || payload.data.length > 512) throw new Error("catalog");
  const seen = new Set();
  for (const model of payload.data) {
    if (!model || typeof model.id !== "string" || !model.id || model.id.length > 512 || /[\s\x00-\x1f]/u.test(model.id) || seen.has(model.id) ||
      (model.capabilities !== undefined && (!Array.isArray(model.capabilities) || model.capabilities.length > 16 || model.capabilities.some(c => typeof c !== "string" || c.length > 64))) ||
      (model.loaded !== undefined && typeof model.loaded !== "boolean") ||
      (model.lan_peer !== undefined && (typeof model.lan_peer !== "string" || !/^[A-Za-z0-9_.-]{1,128}$/.test(model.lan_peer)))) throw new Error("catalog");
    seen.add(model.id);
  }
  return payload.data;
}
async function read(url, headers, timeoutMs, fetchImpl, signal) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {headers, signal: signal ? AbortSignal.any([signal, controller.signal]) : controller.signal, redirect: "error"});
    if (!response.ok) {
      await response.body?.cancel();
      return {status: response.status === 401 || response.status === 403 ? "unknown" : "unavailable", reason: response.status === 401 || response.status === 403 ? "unauthorized" : "host_down"};
    }
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BYTES) { controller.abort(); return {status: "unknown", reason: "invalid_catalog"}; }
      chunks.push(chunk);
    }
    try { return {status: "available", reason: "ok", data: JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(Buffer.concat(chunks)))}; }
    catch { return {status: "unknown", reason: "invalid_catalog"}; }
  } catch { return {status: "unavailable", reason: "host_down"}; }
  finally { clearTimeout(timer); }
}
export async function discover({base = process.env.MLX_BASE_URL || "http://host.docker.internal:11234/v1", key = process.env.MLX_API_KEY || "", peers = peerConfiguration(process.env.MLX_PEER_URLS), timeoutMs = 2000, fetchImpl = fetch, snapshotFile = process.env.MLX_READINESS_FILE, includeObservations = false, signal} = {}) {
  base = endpoint(base);
  // Validate every configured endpoint before making any network request.
  peers = peerConfiguration(JSON.stringify(peers));
  async function probe(name, url, apiKey = "") {
    const headers = apiKey ? {Authorization: `Bearer ${apiKey}`} : {};
    const [health, list] = await Promise.all([read(url.slice(0, -3) + "/health", headers, timeoutMs, fetchImpl, signal), read(url + "/models", headers, timeoutMs, fetchImpl, signal)]);
    let status = "available", reason = "ok", models = [];
    const failure = [health, list].find(r => r.status !== "available");
    if (failure) ({status, reason} = failure);
    else if (health.data?.status !== "ok") { status = "unknown"; reason = "invalid_catalog"; }
    else try { models = catalog(list.data); } catch { status = "unknown"; reason = "invalid_catalog"; }
    return {name, status, reason, checkedAt: Date.now(), modelCount: models.filter(m => !m.lan_peer && !m.id.includes("@")).length, models};
  }
  const observations = await Promise.all([probe("gateway", base, key), ...Object.entries(peers).map(([name, url]) => snapshotFile ? snapshotObservation(snapshotFile, name, url) : probe(name, url))]);
  const gateway = observations[0], byName = new Map(observations.map(h => [h.name, h]));
  for (const model of gateway.models) if (model.lan_peer && !byName.has(model.lan_peer)) {
    const host = {name: model.lan_peer, status: "unknown", reason: "host_unverified", checkedAt: Date.now(), modelCount: 0, models: []};
    observations.push(host);
    byName.set(host.name, host);
  }
  const models = gateway.models.filter(m => !m.capabilities?.length || m.capabilities.includes("chat")).map(m => {
    const peer = m.lan_peer || null, host = peer || "gateway";
    const observation = byName.get(host);
    let availability = observation?.status || "unknown", reason = observation?.reason || "host_unverified";
    const bare = peer && m.id.endsWith("@" + peer) ? m.id.slice(0, -peer.length - 1) : m.id;
    if ((peer && (!Object.hasOwn(peers, peer) || bare === m.id)) || (!peer && m.id.includes("@"))) { availability = "unknown"; reason = "host_unverified"; }
    const live = peer ? observation?.models.find(v => !v.lan_peer && !v.id.includes("@") && v.id === bare) : m;
    if (peer && availability === "available" && (!live || (live.capabilities?.length && !live.capabilities.includes("chat")))) { availability = "unavailable"; reason = "not_advertised"; }
    const current = live || m;
    return {id: m.id, loaded: current.loaded ?? current.state === "ready", capabilities: current.capabilities || [], peer, host,
      state: typeof current.state === "string" && current.state.length < 32 ? current.state : current.loaded ? "ready" : "unloaded", availability, reason};
  });
  const result = {models, hosts: observations.map(({models: ignored, endpointHash: ignoredHash, ...host}) => host), checkedAt: Date.now()};
  if (includeObservations) result.peerObservations = Object.entries(peers).map(([name, url]) => {
    const host = byName.get(name);
    return {...host, endpointHash: endpointHash(url), models: host.models.map(m => ({id: m.id, loaded: m.loaded ?? m.state === "ready", state: m.state, capabilities: m.capabilities || [], ...(m.lan_peer ? {lan_peer: m.lan_peer} : {})}))};
  });
  return result;
}
