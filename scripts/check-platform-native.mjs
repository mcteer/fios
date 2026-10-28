#!/usr/bin/env node
// Source-only, hermetic ownership checks. Never builds/launches installed inference.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, copyFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.length !== 4 || args[0] !== '--source' || args[2] !== '--zig' ||
    !path.isAbsolute(args[1]) || !path.isAbsolute(args[3])) {
  throw new Error('usage: check-platform-native.mjs --source ABS_CHECKOUT --zig ABS_ZIG');
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
  const fixedFiles=['build.zig','lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','src/arch/llama.zig','src/llama_ffi.zig','src/mlx.zig','src/model_registry.zig','src/scheduler.zig','src/server.zig'];
  for(const file of fixedFiles) {
    mkdirSync(path.dirname(path.join(scratch,file)),{recursive:true});
    writeFileSync(path.join(scratch,file),run('git',['--no-replace-objects','-C',source,'show',`${revision}:${file}`],{maxBuffer:16*1024*1024}),{mode:0o600});
  }
  const patch = readFileSync(path.join(root, 'platform/studio/native/mlx-serve-26.10.3.patch'), 'utf8');
  // Fixed reviewed build/roots/registry plus retained target+MTP context bridge.
  assert.deepEqual([...patch.matchAll(/^diff --git (.+)$/gm)].map(m => m[1]),fixedFiles.map(file=>`a/${file} b/${file}`));
  run('git', ['apply', '--check', '-'], { cwd: scratch, input: patch });
  run('git', ['apply', '-'], { cwd: scratch, input: patch });
  for (const name of ['request_ownership.zig', 'control_protocol.zig', 'control_transport.zig', 'device_owner.zig']) {
    copyFileSync(path.join(root, 'platform/studio/native', name), path.join(scratch, 'src', name));
    run(zig, ['ast-check', path.join(scratch, 'src', name)]);
  }
  for (const name of ['device_owner_barrier.cpp', 'device_owner_barrier.h']) copyFileSync(path.join(root, 'platform/studio/native', name), path.join(scratch, 'lib', name));
  for(const file of fixedFiles.filter(file=>file.endsWith('.zig'))) run(zig,['ast-check',path.join(scratch,file)]);
  for (const optimize of ['Debug', 'ReleaseSafe']) {
    run(zig, ['test', path.join(root, 'platform/studio/native/request_ownership_test.zig'), '-O', optimize]);
    run(zig, ['test', path.join(root, 'platform/studio/native/control_protocol.zig'), '-O', optimize]);
    run(zig, ['test', path.join(root, 'platform/studio/native/device_owner_test.zig'), '-O', optimize]);
    run(zig, ['test', path.join(root, 'platform/studio/native/registry_hold_test.zig'), '-O', optimize]);
  }
  // Characterization guards supplement runtime tests; they do not establish
  // all-backend coverage. Every reviewed production atomic borrow mutation
  // must advance the independently bounded partial-probe epoch under its lock.
  const registrySource=readFileSync(path.join(scratch,'src/model_registry.zig'),'utf8');
  const schedulerSource=readFileSync(path.join(scratch,'src/scheduler.zig'),'utf8');
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
  const patched = readFileSync(path.join(scratch, 'src/server.zig'), 'utf8');
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
