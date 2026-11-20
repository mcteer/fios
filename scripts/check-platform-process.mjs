import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { createConnection } from 'node:net';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

// Explicitly local disposable manager processes; no host service commands.
if (process.argv.length !== 3 || process.argv[2] !== '--isolated') throw new Error('Usage: node scripts/check-platform-process.mjs --isolated');
const root = fileURLToPath(new URL('../', import.meta.url));
const built = spawnSync('swift', ['build', '--package-path', 'platform/studio'], { cwd: root, encoding: 'utf8', timeout: 120_000 });
assert.equal(built.status, 0, 'Native package build failed');
const shown = spawnSync('swift', ['build', '--package-path', 'platform/studio', '--show-bin-path'], { cwd: root, encoding: 'utf8', timeout: 30_000 });
assert.equal(shown.status, 0);
const bin = shown.stdout.trim();
const state = mkdtempSync('/tmp/fios009-process-');
const children = [];
function start(name) {
  const child = spawn(join(bin, name), ['--state', state], { stdio: 'ignore' });
  children.push(child);
  return child;
}
function status(operation='status') {
  const result = spawnSync(join(bin, 'studioctl'), ['--state', state, operation], { encoding: 'utf8', timeout: 3000 });
  if (result.status !== 0) return null;
  return JSON.parse(result.stdout);
}
function task(operation,payload) {
  const request={version:1,id:randomUUID(),operation,payload};
  const result=spawnSync(join(bin,'studioctl'),['--state',state,'task'],{input:JSON.stringify(request),encoding:'utf8',timeout:3000});
  return result.stdout ? JSON.parse(result.stdout) : null;
}
async function until(test, milliseconds = 15_000) {
  const deadline = Date.now() + milliseconds;
  while (Date.now() < deadline) { const result = test(); if (result) return result; await delay(100); }
  throw new Error('Isolated process acceptance deadline');
}
let managedPID;
try {
  const supervisor = start('studio-supervisor');
  await until(() => status());
  const first = JSON.parse(readFileSync(join(state, 'progress.json')));
  managedPID = first.pid;
  assert.equal(status().sandbox_admission, 'disabled');
  const owner=randomBytes(32).toString('base64');
  const proposed=task('job.create',{owner,phase:'begin',idempotency:randomUUID(),kind:'sandbox',length:0,sha256:createHash('sha256').update('').digest('hex'),lifetime:900000,model:null,image:'sha256:'+'a'.repeat(64),memory:512*1024*1024,cpus:1});
  assert.equal(proposed?.ok,false);assert.equal(proposed.error,'native_unsupported','Task IPC must not bypass unenrolled activation');
  const foreign=task('job.status',{owner,job:randomUUID()});
  assert.equal(foreign?.error,'unauthorized');
  assert.equal(task('service.desired',{owner,service:'mlx',desired:'stopped'}),null,'Task CLI must reject management role before connecting');
  assert.equal(status().services.mlx.desired,'running','Task data changed native desired state');
  const independent=status('supervisor');
  assert.equal(independent?.supervisor?.state,'running','Supervisor must be independently observable through CLI');
  assert.ok(independent.supervisor.starts>=1&&independent.supervisor.starts<=3);
  const activity=status('activity');
  assert.equal(activity.activity,'unknown');
  assert.equal(activity.observation.coverage,'unsupported');
  assert.equal(activity.observation.outstanding_owners,null);
  assert.equal(activity.observation.loading,null);
  assert.match(activity.observation.profile_hash,/^[a-f0-9]{64}$/);
  const exported=status('export');
  assert.equal(exported?.version,2,'Detailed read-only export command is missing');
  assert.equal(exported.manager_epoch,activity.observation.manager_epoch);
  assert.equal(exported.native_epoch,activity.observation.native_epoch);
  assert.equal(exported.coverage,'unsupported');assert.equal(exported.outstanding_owners,null);
  assert.equal('ok' in exported,false,'Exporter leaked control envelope instead of observation frame');
  for(const environment of [{SSH_ORIGINAL_COMMAND:'service.force mlx'},{SSH_TTY:'/dev/fixture-pty'}]) {
    const refused=spawnSync(join(bin,'studioctl'),['--state',state,'export'],{stdio:'ignore',timeout:2000,
      env:{PATH:'/usr/bin:/bin',HOME:process.env.HOME,...environment}});
    assert.equal(refused.status,2,'Forced observation export accepted alternate command/PTY');
  }
  assert.ok(status(),'Rejected forced-command data changed manager control state');
  const resourceFrame=await until(()=>{const frame=status('resources');return typeof frame?.resources?.cpu==='number' ? frame : null;},8000);
  const {resources,resource_observation:resourceObservation}=resourceFrame;
  assert.ok(resources.cpu>=0&&resources.cpu<=100);
  assert.equal(resources.vmAvailable,null); // Unverified VM remains explicitly unknown.
  assert.ok(resources.gpu===null||(typeof resources.gpu==='number'&&resources.gpu>=0&&resources.gpu<=100));
  for(const key of ['gpu_in_use_bytes','gpu_allocated_bytes'])assert.ok(resources[key]===null||(Number.isSafeInteger(resources[key])&&resources[key]>=0));
  assert.ok(Number.isSafeInteger(resources.sampledAt)&&Date.now()-resources.sampledAt<=5000&&resources.sampledAt<=Date.now()+1000);
  assert.ok(['unavailable','observed_registry'].includes(resourceObservation.gpu_coverage));assert.equal(resourceObservation.vm_coverage,'unknown');
  assert.equal(resourceObservation.vm_sampled_at,null);assert.equal(resourceObservation.vm_epoch,null);
  assert.equal(resourceObservation.version,2);
  assert.deepEqual(Object.keys(resourceObservation.signals).sort(),['available_memory','cpu','disk_free','gpu','gpu_allocated_memory','gpu_in_use_memory','low_power_mode','physical_memory','pressure','thermal','vm_available'].sort());
  for(const key of ['physical_memory','cpu','disk_free','low_power_mode']) {
    const signal=resourceObservation.signals[key];assert.equal(signal.availability,'observed');
    assert.ok(Number.isSafeInteger(signal.sampled_at));assert.ok(Number.isSafeInteger(signal.age_ms)&&signal.age_ms>=-1000&&signal.age_ms<=5000);
    assert.equal(signal.age_ms,resourceObservation.observed_at-signal.sampled_at);
  }
  assert.deepEqual(resourceObservation.signals.vm_available,{availability:'unknown',sampled_at:null,age_ms:null});
  assert.equal(resources.vmSampledAt,null);
  assert.equal(resourceObservation.sampled_at,resources.sampledAt);
  assert.equal(typeof resources.lowPowerMode,'boolean');
  assert.match(resourceObservation.epoch,/^[a-f0-9-]{36}$/);assert.ok(Number.isSafeInteger(resourceObservation.sequence));
  const repeated=await until(()=>{
    const before=status('resources')?.resource_observation,after=status('resources')?.resource_observation;
    return before&&after&&before.sequence===after.sequence ? [before,after] : null;
  },4000);
  assert.equal(repeated[0].epoch,repeated[1].epoch);
  for(const signal of ['physical_memory','disk_free','cpu'])
    assert.equal(repeated[0].signals[signal].sampled_at,repeated[1].signals[signal].sampled_at,`${signal} was redated at read time`);
  const nextResources=await until(()=>{
    const next=status('resources')?.resource_observation;
    return next&&next.sequence>repeated[1].sequence ? next:null;
  },6000);
  assert.equal(nextResources.epoch,repeated[1].epoch);
  assert.ok(nextResources.sampled_at>repeated[1].sampled_at,'Advancing sequence reused the host measurement time');
  assert.equal(nextResources.signals.vm_available.availability,'unknown');
  const liveBackup=spawnSync(join(bin,'studioctl'),['--state',state,'backup','--to',join(state,'snapshot.sqlite')],{encoding:'utf8',timeout:3000});
  assert.equal(liveBackup.status,1,'Offline backup must refuse a live manager');
  const duplicate = start('studio-manager');
  await until(() => duplicate.exitCode !== null);
  assert.equal(duplicate.exitCode, 1, 'Duplicate manager must fail before touching active sockets');
  assert.ok(status());
  const slow=createConnection(join(state,'control.sock'));
  slow.on('error',()=>{});
  await new Promise(resolve=>slow.once('connect',resolve));
  slow.write(Buffer.from([0]));
  await delay(100);
  try {
    const began=performance.now();
    assert.ok(status(),'Partial operator frame blocked observation');
    assert.ok(performance.now()-began<1000,'A partial IPC client stalled the manager resource/heartbeat loop');
  } finally { slow.destroy(); }
  process.kill(managedPID, 'SIGKILL');
  const second = await until(() => {
    try { const next = JSON.parse(readFileSync(join(state, 'progress.json'))); return next.pid !== first.pid && status() ? next : null; } catch { return null; }
  });
  managedPID = second.pid;
  assert.notEqual(second.epoch, first.epoch);
  const afterRestart=await until(()=>{
    const resource=status('resources');
    return resource?.resource_observation?.epoch===second.epoch ? resource:null;
  },4000);
  assert.notEqual(afterRestart.resource_observation.epoch,nextResources.epoch);
  assert.equal(afterRestart.resource_observation.signals.vm_available.availability,'unknown');
  const restartedCPU=await until(()=>{
    const observation=status('resources')?.resource_observation;
    return observation?.epoch===second.epoch&&observation.signals.cpu.availability==='observed' ? observation.signals.cpu:null;
  },8000);
  assert.ok(restartedCPU.sampled_at>nextResources.sampled_at,'New manager reused predecessor CPU sample');
  process.kill(managedPID, 'SIGSTOP');
  assert.ok(status('supervisor')?.supervisor,'Supervisor status must not depend on a responsive manager');
  const third = await until(() => {
    try { const next = JSON.parse(readFileSync(join(state, 'progress.json'))); return next.pid !== second.pid && status() ? next : null; } catch { return null; }
  }, 20_000);
  managedPID = third.pid;
  assert.notEqual(third.epoch, second.epoch);
  supervisor.kill('SIGTERM');
  await until(() => supervisor.exitCode !== null);
  await until(() => { try { process.kill(managedPID, 0); return false; } catch { return true; } });
  managedPID = undefined;
  const stoppedBackup=spawnSync(join(bin,'studioctl'),['--state',state,'backup','--to',join(state,'snapshot.sqlite')],{encoding:'utf8',timeout:3000});
  assert.equal(stoppedBackup.status,0,'Stopped platform journal snapshot failed');
  const receipt=JSON.parse(stoppedBackup.stdout);
  assert.equal(receipt.scope,'platform_journal_only');assert.equal(receipt.schema,9);assert.match(receipt.sha256,/^[a-f0-9]{64}$/);
  const bundle=join(state,'state-bundle');
  const savedState=spawnSync(join(bin,'studioctl'),['--state',state,'backup-state','--to',bundle],{encoding:'utf8',timeout:5000});
  assert.equal(savedState.status,0,'Stopped journal+empty-export bundle failed');
  const savedReceipt=JSON.parse(savedState.stdout);
  assert.equal(savedReceipt.scope,'platform_journal_and_exports');assert.equal(savedReceipt.artifacts,0);
  const verified=spawnSync(join(bin,'studioctl'),['--state',bundle,'verify-backup','--sha256',savedReceipt.sha256],{encoding:'utf8',timeout:5000});
  assert.equal(verified.status,0,'Private bundle verification failed');
  assert.equal(JSON.parse(verified.stdout).sha256,savedReceipt.sha256);
  const restored=spawnSync(join(bin,'studioctl'),['--state',bundle,'restore-state','--sha256',savedReceipt.sha256,'--to',join(state,'restored-state')],{encoding:'utf8',timeout:5000});
  assert.equal(restored.status,0,'Verified restoration to a fresh private state directory failed');
  assert.equal(JSON.parse(restored.stdout).started,false,'Restore must not start any application or replay work');
  console.log('PASS: isolated manager/task-owner IPC with activation closed, fixed read-only export/alternate-command/PTY rejection, duplicate exclusion, crash recovery, stopped-loop watchdog and child cleanup');
} finally {
  if (managedPID) { try { process.kill(managedPID, 'SIGKILL'); } catch {} }
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
  await delay(300);
  for (const child of children) if (child.exitCode === null) child.kill('SIGKILL');
  // Exit/signals are not stopped-writer proof. The offline command acquires
  // both supervisor+manager locks before opening this disposable journal.
  const proof=spawnSync(join(bin,'studioctl'),['--state',state,'backup','--to',join(state,'cleanup-proof.sqlite')],{stdio:'ignore',timeout:5000});
  if(proof.status===0)rmSync(state, { recursive: true, force: true });
  else console.log('RETAINED: isolated process state; stopped writer proof unavailable: '+state);
}
