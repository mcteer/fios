#!/usr/bin/env node
// Source-only, hermetic ownership checks. Never builds/launches installed inference.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, copyFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import {verifyLlamaCustody} from './lib/platform-native-llama-custody.mjs';
import {verifyDs4Custody} from './lib/platform-native-ds4-custody.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const mutateCapture=args.length===5&&args[4]==='--mutate-capture-sequence';
const mutateLineageMissing=args.length===5&&args[4]==='--mutate-lineage-missing';
const mutateCorrelation=args.length===5&&args[4]==='--mutate-request-correlation';
const mutatePrimary=args.length===5&&args[4]==='--mutate-primary-conflict';
if ((args.length !== 4 && !mutateCapture && !mutatePrimary && !mutateCorrelation && !mutateLineageMissing) || args[0] !== '--source' || args[2] !== '--zig' ||
    !path.isAbsolute(args[1]) || !path.isAbsolute(args[3])) {
  throw new Error('usage: check-platform-native.mjs --source ABS_CHECKOUT --zig ABS_ZIG [--mutate-capture-sequence|--mutate-primary-conflict|--mutate-request-correlation|--mutate-lineage-missing]');
}
const source = args[1], zig = args[3];
const run = (exe, argv, options = {}) => execFileSync(exe, argv, {
  encoding: 'utf8', timeout: 120_000, stdio: ['pipe', 'pipe', 'pipe'], ...options,
});
const revision = '046b647686419df06c6c7132fb1d15d76185c3e5';
assert.equal(run('git', ['--no-replace-objects', '-C', source, 'rev-parse', 'HEAD']).trim(), revision, 'unreviewed native revision');
assert.equal(run(zig, ['version']).trim(), '0.17.0', 'unreviewed Zig version');
const scratch = mkdtempSync(path.join(tmpdir(), 'fios-native-source-check-'));
try {
  const fixedFiles=['build.zig','lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','src/arch/ds4.zig','src/arch/ds4_stub.zig','src/arch/llama.zig','src/arch/llama_stub.zig','src/arch/mlx_stream.zig','src/arch/mlx_stream_stub.zig','src/llama_ffi.zig','src/main.zig','src/mlx.zig','src/model_registry.zig','src/scheduler.zig','src/server.zig','src/transformer.zig'];
  for(const file of fixedFiles) {
    mkdirSync(path.dirname(path.join(scratch,file)),{recursive:true});
    writeFileSync(path.join(scratch,file),run('git',['--no-replace-objects','-C',source,'show',`${revision}:${file}`],{maxBuffer:16*1024*1024}),{mode:0o600});
  }
  const patch = readFileSync(path.join(root, 'platform/studio/native/mlx-serve-26.10.3.patch'), 'utf8');
  // Fixed reviewed build/roots/registry plus retained target+MTP context bridge.
  assert.deepEqual([...patch.matchAll(/^diff --git (.+)$/gm)].map(m => m[1]),fixedFiles.map(file=>`a/${file} b/${file}`));
  run('git', ['apply', '--check', '-'], { cwd: scratch, input: patch });
  run('git', ['apply', '-'], { cwd: scratch, input: patch });
  const entry=readFileSync(path.join(scratch,'src/main.zig'),'utf8');
  const readOnly=entry.indexOf('if (args.len == 2 and std.mem.eql(u8, args[1], "--version"))');
  const startup=entry.indexOf('Guard.start(VERSION)'),backend=entry.indexOf('server_mod.applyMlxCacheLimit();');
  assert(readOnly>=0&&readOnly<startup&&startup<backend,'FIO_NATIVE_READONLY_STARTUP_ORDER');
  verifyLlamaCustody(readFileSync(path.join(scratch,'src/arch/llama.zig'),'utf8'),readFileSync(path.join(scratch,'src/model_registry.zig'),'utf8'));
  verifyDs4Custody(readFileSync(path.join(scratch,'src/arch/ds4.zig'),'utf8'),readFileSync(path.join(scratch,'src/model_registry.zig'),'utf8'));
  for (const name of ['backend_lifetime.zig', 'request_ownership.zig', 'control_protocol.zig', 'control_transport.zig', 'device_owner.zig', 'startup_guard.zig']) {
    copyFileSync(path.join(root, 'platform/studio/native', name), path.join(scratch, 'src', name));
    run(zig, ['ast-check', path.join(scratch, 'src', name)]);
  }
  for (const name of ['device_owner_barrier.cpp', 'device_owner_barrier.h']) copyFileSync(path.join(root, 'platform/studio/native', name), path.join(scratch, 'lib', name));
  for(const file of fixedFiles.filter(file=>file.endsWith('.zig'))) run(zig,['ast-check',path.join(scratch,file)]);
  let ownershipTests=path.join(root,'platform/studio/native/request_ownership_test.zig');
  if(mutateCapture||mutatePrimary||mutateCorrelation){
    const directory=path.join(scratch,'capture-mutation');mkdirSync(directory,{mode:0o700});
    const original=readFileSync(path.join(root,'platform/studio/native/request_ownership.zig'),'utf8');
    const check=mutateCapture?'} else self.sample_sequence += 1;':mutateCorrelation?'descendant.correlation = original.correlation;':'if (!std.mem.eql(u8, identity.id[0..identity.len], model)) return error.ModelConflict;';assert.equal(original.split(check).length,2,'native guard boundary changed');
    writeFileSync(path.join(directory,'request_ownership.zig'),original.replace(check,mutateCapture?'} else {}':mutateCorrelation?'descendant.correlation = null;':'_ = std.mem.eql(u8, identity.id[0..identity.len], model);'));
    ownershipTests=path.join(directory,'request_ownership_test.zig');copyFileSync(path.join(root,'platform/studio/native/request_ownership_test.zig'),ownershipTests);
  }
  let protocolTests=path.join(root,'platform/studio/native/control_protocol.zig');
  if(mutateLineageMissing){
    const directory=path.join(scratch,'lineage-mutation');mkdirSync(directory,{mode:0o700});
    for(const name of ['request_ownership.zig','device_owner.zig'])copyFileSync(path.join(root,'platform/studio/native',name),path.join(directory,name));
    const original=readFileSync(protocolTests,'utf8'),check='response[7] = @intFromBool(snapshot.uncertain);';
    assert.equal(original.split(check).length,2,'native lineage unknown boundary changed');
    protocolTests=path.join(directory,'control_protocol.zig');
    writeFileSync(protocolTests,original.replace(check,'response[7] = @intFromBool(snapshot.uncertain and snapshot.found);'));
  }
  for (const optimize of ['Debug', 'ReleaseSafe']) {
    run(zig, ['test', ownershipTests, '-O', optimize]);
    run(zig, ['test', protocolTests, '-O', optimize]);
    run(zig, ['test', path.join(root, 'platform/studio/native/device_owner_test.zig'), '-O', optimize]);
    run(zig, ['test', path.join(root, 'platform/studio/native/registry_hold_test.zig'), '-O', optimize]);
  }
  assert(readFileSync(path.join(root,'platform/studio/native/request_ownership.zig'),'utf8').includes('pub var shared: Tracker = .{ .primary_guard = true };'),'serving singleton must protect primary binding');
  const mainSource=readFileSync(path.join(scratch,'src/main.zig'),'utf8');
  const startupCall=mainSource.indexOf('@import("startup_guard.zig").Guard.start(VERSION)');
  assert(startupCall>mainSource.indexOf('pub fn main('));
  assert(startupCall<mainSource.indexOf('crt.exportHomeDefault();'),'fixture guard must precede native initialization');
  // Characterization guards supplement runtime tests; they do not establish
  // all-backend coverage. Every reviewed production atomic borrow mutation
  // must advance the independently bounded partial-probe epoch under its lock.
  const registrySource=readFileSync(path.join(scratch,'src/model_registry.zig'),'utf8');
  const schedulerSource=readFileSync(path.join(scratch,'src/scheduler.zig'),'utf8');
  const cpuLoadStart=schedulerSource.slice(schedulerSource.indexOf('fn doLoadOnInferenceThread('));
  const cpuGuard=cpuLoadStart.indexOf('if (!params.entry.fiosCanReplaceCpuState()) return error.RegistryHeld;');
  assert(cpuGuard>=0&&cpuGuard<cpuLoadStart.indexOf('FiosActorLoadPreparation.begin('),'known unsafe CPU state must refuse before backend preparation');
  // Supplemental wiring proof only; real-model backend acceptance is separate.
  for(const name of ['doLoadDs4OnInferenceThread','doLoadLlamaOnInferenceThread','aneBuild','doLoadGenOnInferenceThread','doLoadOnInferenceThread']){
    const start=schedulerSource.indexOf(`fn ${name}(`);assert(start>=0);
    const remainder=schedulerSource.slice(start+3),next=remainder.search(/\n(?:pub )?fn /);
    const body=schedulerSource.slice(start,next<0?undefined:start+3+next);
    const handoff='try installRetainedCpuState(entry, params);';
    assert.equal(body.split(handoff).length,2,'one checked CPU ownership handoff per loader');
    const [before,after]=body.split(handoff);
    assert(!/\bentry\.\w+\s*=(?!=)/.test(before),'entry ownership written before checked CPU handoff');
    assert(!/\btry\s/.test(after),'fallible work after entry ownership transfer');
  }

  // Separately reviewed aggregate drop: one mutex transaction advances epoch
  // BEFORE bounded exact-set ref drops and gate clear; no backend/destruction.
  const pinDrop='        self.fios_probe_epoch += 1; // exhaustion checked BEFORE refs/gate clear\n        for (pins) |entry| _ = entry.refcount.fetchSub(1, .acq_rel);';
  assert.equal(registrySource.split(pinDrop).length,2,'unreviewed aggregate pin-drop transaction');
  const accessRelease=registrySource.slice(registrySource.indexOf('pub fn fiosReleaseAccessPins('),registrySource.indexOf('pub fn fiosProbeChangedLocked('));
  assert(accessRelease.includes('self.mutex.lockUncancelable(self.io);')&&accessRelease.includes('defer self.mutex.unlock(self.io);'));
  for(const guard of ['self.fios_probe_epoch == std.math.maxInt(u64)','pins.len != self.fios_access_pin_count','entry.refcount.load(.acquire) != 1']){
    const position=accessRelease.indexOf(guard);assert(position>=0&&position<accessRelease.indexOf(pinDrop),'missing pre-drop transaction guard');
  }
  assert(accessRelease.indexOf(pinDrop)<accessRelease.indexOf('self.fios_access_ticket = 0;'));
  const registryOrdinary=registrySource.split('\ntest ')[0].replace(pinDrop,'        // Reviewed aggregate pin-drop transaction characterized above.');
  const slotStart=schedulerSource.indexOf('pub const SlotState');
  const schedulerProduction=schedulerSource.slice(0,schedulerSource.indexOf('\ntest "fios native cleanup'))+schedulerSource.slice(slotStart,schedulerSource.indexOf('\ntest ',slotStart));
  for(const [text,marker,count] of [[registryOrdinary,'self.fiosProbeChangedLocked();',2],[schedulerProduction,'self.registry.fiosProbeChangedLocked();',2]]) {
    assert.equal([...text.matchAll(/\.refcount\.(?:fetchAdd|fetchSub|store|swap|cmpxchgWeak|cmpxchgStrong)\(/g)].length,count,'unreviewed production atomic reference mutation');
    const mutations=[...text.matchAll(/\b\w+\.refcount\.fetch(?:Add|Sub)\(1, \.acq_rel\);/g)];
    assert.equal(mutations.length,count,'unreviewed production reference mutation set');
    for(const match of mutations) assert(text.slice(match.index+match[0].length).trimStart().startsWith(marker),'borrow mutation lacks partial epoch advancement');
  }
  const genPosting=schedulerSource.slice(schedulerSource.indexOf('pub fn runGeneration('));
  assert(genPosting.indexOf('FiosActorLoadPreparation.beginActive(')<genPosting.indexOf('self.gen_queue.append('));
  assert(genPosting.includes('req.fios_parent = fios_sender.token;'));
  const genActor=schedulerSource.slice(schedulerSource.indexOf('fn runGenRequests('));
  assert(genActor.indexOf('fios_actor_context.begin(sch, reqs)')<genActor.indexOf('req.model.gen_busy = true;'));
  assert(schedulerSource.includes('self.held = try source.retainTokens(sch.io, tokens[0..reqs.len]);'));
  assert(schedulerSource.includes('req.merge.?.run_many(ctxs[0..reqs.len]);'),'native merging must remain available');
  for (const [signature, call, work] of [
    ['fn runPrefill(sch:', 'beginSlots(sch, &.{slot})', 'const observe ='],
    ['fn runDecodeTick(sch:', 'beginSlots(sch, active)', 'defer sch.inflight_generated_tokens'],
  ]) {
    const actor = schedulerSource.slice(schedulerSource.indexOf(signature));
    assert(actor.indexOf(call) >= 0 && actor.indexOf(call) < actor.indexOf(work), 'text actor context must precede backend work');
    assert(actor.indexOf('defer fios_actor_context.finish(sch.io);') < actor.indexOf(work), 'text actor must restore context on every exit');
  }
  const patched = readFileSync(path.join(scratch, 'src/server.zig'), 'utf8');
  const startupEnrollment=patched.indexOf('load_params.registry.fios_request_tracker = fios_requests;');
  assert(startupEnrollment>0&&startupEnrollment<patched.indexOf('var startup: StartupResponder'), 'tracker must precede startup responder/load');
  assert(startupEnrollment<patched.indexOf('var scheduler = try scheduler_mod.Scheduler.init('), 'startup load cannot precede tracker enrollment');
  const actorStart=schedulerSource.indexOf('fn doLoadOnInferenceThread(');
  const actorEnd=schedulerSource.indexOf('\nfn ',actorStart+1),actorLoad=schedulerSource.slice(actorStart,actorEnd);
  const actorGuard=actorLoad.indexOf('try FiosActorLoadPreparation.begin(sch, params.entry.id, params.fios_parent)');
  assert(actorGuard>=0&&actorGuard<actorLoad.indexOf('params.entry.load_progress.start('), 'actor guard must precede every backend load branch');
  assert(schedulerSource.includes('.fios_parent = fios_preparation,'), 'queued load must carry its original preparation owner');
  for(const [producer,queue,handler,backend] of [
    ['pub fn computeEmbeddings(', 'self.embed_queue.append(', 'fn runEmbedRequest(', 'req.model.transformer.?'],
    ['pub fn encodeVision(', 'self.vision_queue.append(', 'fn runVisionEncode(', 'req.model.vision_encoder'],
  ]){
    const posting=schedulerSource.slice(schedulerSource.indexOf(producer));
    assert(posting.indexOf('req.fios_parent = fios_ownership.current;')>=0&&posting.indexOf('req.fios_parent = fios_ownership.current;')<posting.indexOf(queue),'encoder queue lost caller ownership');
    const handling=schedulerSource.slice(schedulerSource.indexOf(handler));
    assert(handling.indexOf('FiosActorLoadPreparation.beginActive(')>=0&&handling.indexOf('FiosActorLoadPreparation.beginActive(')<handling.indexOf(backend),'encoder actor guard must precede backend access');
  }

  assert(patched.indexOf('fios_requests.enter(io)') < patched.indexOf('std.Thread.spawn(.{}, handleConnectionThread'));
  const thread = patched.slice(patched.indexOf('fn handleConnectionThread('), patched.indexOf('const MAX_JSON_DEPTH'));
  assert(thread.indexOf('defer fios_requests.leave(ownership_io, ownership)') >= 0);
  assert(thread.indexOf('defer fios_requests.leave(ownership_io, ownership)') < thread.indexOf('defer conn.close()'));
  assert(patched.indexOf('try fios_requests.bind(stream.io, ownership, entry.id)') < patched.indexOf('const lm = scheduler.ensureLoaded(if (ownership_entry) |entry| entry.id else requested_model_id)'));
  assert(patched.includes('fios_ownership.renderSnapshot(snapshot, &activity_buffer)'));
  assert(patched.includes('if (!peerIsLoopback(stream) or isTunneledRequest(request[0..header_end_pos]))'));
  console.log('Pinned source patch applies; syntax and Debug/ReleaseSafe ownership tests pass.');
  console.log('Coverage remains unknown. This checker does not compile/link the full server or run HTTP tests.');
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
