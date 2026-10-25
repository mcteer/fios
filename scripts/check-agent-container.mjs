// Isolated integration/upgrade/rollback rehearsal. Never uses production Compose or its volume.
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import { createServer } from "node:net";

const root = fileURLToPath(new URL("../", import.meta.url));
const id = randomUUID().slice(0, 12),
  project = "fios-agent-test-" + id;
const image = "fios-agent-test:" + id,
  previous = process.env.FIOS_AGENT_ROLLBACK_IMAGE || "fios:0.1.0";
const log = join(tmpdir(), project + ".log");
const probe = createServer();
await new Promise((resolve) => probe.listen(0, "127.0.0.1", resolve));
const port = probe.address().port;
await new Promise((resolve) => probe.close(resolve));
const env = {
  ...process.env,
  FIOS_AGENT_TEST_IMAGE: image,
  FIOS_AGENT_TEST_PORT: String(port),
};
async function command(args, { capture = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn("docker", args, {
      cwd: root,
      env,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    for (const stream of [child.stdout, child.stderr])
      stream.on("data", (b) => {
        appendFileSync(log, b);
        if (capture) output += b;
      });
    child.on("error", reject);
    child.on("exit", (code) =>
      code === 0
        ? resolve(output.trim())
        : reject(new Error("Isolated Docker command failed; see " + log)),
    );
  });
}
const compose = (...args) =>
  command(
    [
      "compose",
      "--env-file",
      "/dev/null",
      "-p",
      project,
      "-f",
      "tests/compose.agent.yaml",
      ...args,
    ],
    { capture: true },
  );
let origin, cookie, chatId;
async function login() {
  origin = "http://127.0.0.1:" + port;
  const r = await fetch(origin + "/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password: "isolated-container-test-password" }),
  });
  assert.equal(r.status, 200);
  cookie = r.headers.get("set-cookie").split(";")[0];
}
const request = (path, options = {}) =>
  fetch(origin + path, {
    ...options,
    headers: { Cookie: cookie, Origin: origin, ...options.headers },
  });
async function send(content) {
  const f = new FormData();
  f.set("content", content);
  f.set("model", "test/coding-model");
  return request(`/api/chats/${chatId}/messages`, { method: "POST", body: f });
}
try {
  await command(["image", "inspect", previous, "--format", "{{.Id}}"]);
  await command(["build", "-t", image, "."]);
  env.FIOS_AGENT_TEST_IMAGE = previous;
  await compose("up", "-d", "--wait");
  await login();
  chatId = (await (await request("/api/chats", { method: "POST" })).json()).id;
  assert.match(
    await (await send("synthetic before upgrade")).text(),
    /event: done/,
  );
  const original = await (await request(`/api/chats/${chatId}`)).json();
  assert.equal(original.messages.length, 2);
  await compose("stop", "app");
  await compose(
    "run",
    "--rm",
    "--no-deps",
    "--entrypoint",
    "node",
    "app",
    "-e",
    "require('node:fs').copyFileSync('/app/data/fios.sqlite','/app/data/pre-agent-backup.sqlite')",
  );
  env.FIOS_AGENT_TEST_IMAGE = image;
  await compose("up", "-d", "--wait");
  await login();
  const upgraded = await (await request(`/api/chats/${chatId}`)).json();
  assert.deepEqual(upgraded.messages, original.messages);
  assert.match(
    await (await send("after harness upgrade")).text(),
    /event: delta/,
  );
  const stream = await send("SLOW_RESPONSE");
  const reader = stream.body.getReader();
  let text = "";
  while (!text.includes("event: delta")) {
    const next = await reader.read();
    assert.equal(next.done, false);
    text += new TextDecoder().decode(next.value);
  }
  const stoppedAt = Date.now();
  await request(`/api/chats/${chatId}/stop`, { method: "POST" });
  while (!(await reader.read()).done) {}
  assert.ok(
    Date.now() - stoppedAt < 2000,
    "container cancellation exceeded two seconds",
  );
  assert.equal(
    (await (await request(`/api/chats/${chatId}`)).json()).generating,
    false,
  );
  const limits = JSON.parse(
    await command(
      [
        "inspect",
        "--format",
        "{{json .HostConfig}}",
        await compose("ps", "-q", "app"),
      ],
      { capture: true },
    ),
  );
  assert.equal(limits.Memory, 1073741824);
  assert.equal(limits.ReadonlyRootfs, true);
  assert.equal(limits.NanoCpus, 2000000000);
  const runtime = await compose(
    "exec",
    "-T",
    "app",
    "/opt/venv/bin/python",
    "-I",
    "-B",
    "-c",
    "import os,sys,platform;from importlib.metadata import version;assert os.getuid()==1000;assert version('pydantic-ai-slim')=='2.61.0';print(platform.machine(),sys.version.split()[0])",
  );
  assert.match(runtime, /aarch64 3\.11\.17/);
  // A second client here never opens SQLite: only the main Express instance owns the DB.
  await compose(
    "exec",
    "-T",
    "app",
    "node",
    "--input-type=module",
    "-e",
    `
  import {AgentClient} from './src/agent/client.js';
  const c=new AgentClient(); const b=Buffer.alloc(10*1024*1024,120);Buffer.from('89504e470d0a1a0a','hex').copy(b);
  const url='data:image/png;base64,'+b.toString('base64');
  try{for await(const e of c.run({model:'test/coding-model',context:[{role:'user',content:[{type:'text',text:'🧵'.repeat(200000)},...Array.from({length:2},()=>({type:'image_url',image_url:{url}}))]}]})){await new Promise(r=>setTimeout(r,30));}}
  finally{await c.close();}console.log('bounded-context-ok');`,
  );
  // Kill a test parent inside the container; Compose init must reap its orphan.
  await compose(
    "exec",
    "-T",
    "app",
    "node",
    "--input-type=module",
    "-e",
    `
  import {spawn} from 'node:child_process';import {readFileSync,existsSync} from 'node:fs';
  const source=\"import {AgentClient} from './src/agent/client.js';const c=new AgentClient();await c.ready();console.log(c.pid);setInterval(()=>{},1000);\";
  const p=spawn(process.execPath,['--input-type=module','-e',source],{stdio:['ignore','pipe','ignore']});
  const pid=await new Promise((resolve,reject)=>{let s='';p.stdout.on('data',b=>{s+=b;if(s.includes('\\n'))resolve(Number(s.trim()));});setTimeout(()=>reject(new Error('readiness timeout')),5000).unref();});
  p.kill('SIGKILL');let live=true;
  for(let i=0;i<100;i++){const f='/proc/'+pid+'/stat';if(!existsSync(f)||readFileSync(f,'utf8').split(' ')[2]==='Z'){live=false;break;}await new Promise(r=>setTimeout(r,20));}
  if(live)throw new Error('orphan worker');console.log('parent-death-cleanup-ok');`,
  );
  const peak = Number(
    await compose(
      "exec",
      "-T",
      "app",
      "node",
      "-e",
      "console.log(require('node:fs').readFileSync('/sys/fs/cgroup/memory.peak','utf8').trim())",
    ),
  );
  assert.ok(peak < 1073741824);
  console.log(
    "ARM64 hardened image passed; peak memory MiB:",
    Math.ceil(peak / 1048576),
  );
  const after = await (await request(`/api/chats/${chatId}`)).json();
  await compose("stop", "app");
  env.FIOS_AGENT_TEST_IMAGE = previous;
  await compose("up", "-d", "--wait");
  await login();
  const rolled = await (await request(`/api/chats/${chatId}`)).json();
  assert.deepEqual(rolled.messages, after.messages);
  await compose("stop", "app");
  // Restore the actual stopped-volume backup as a separate rehearsal.
  await compose(
    "run",
    "--rm",
    "--no-deps",
    "--entrypoint",
    "node",
    "app",
    "-e",
    "const fs=require('node:fs');for(const s of ['-wal','-shm'])fs.rmSync('/app/data/fios.sqlite'+s,{force:true});fs.copyFileSync('/app/data/pre-agent-backup.sqlite','/app/data/fios.sqlite')",
  );
  await compose("up", "-d", "--wait");
  await login();
  assert.deepEqual(
    (await (await request(`/api/chats/${chatId}`)).json()).messages,
    original.messages,
  );
  console.log(
    "Isolated old → harness → old image rollback and backup restore passed.",
  );
  console.log(
    "Images:",
    previous,
    "→",
    image,
    "(temporary test image removed after validation)",
  );
  console.log("Build/test log:", log);
} finally {
  await compose("down", "--volumes", "--remove-orphans").catch(() => {});
  await command(["image", "rm", image]).catch(() => {});
}
