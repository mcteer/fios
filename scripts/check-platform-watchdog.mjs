import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

// Actual disposable supervisor + trusted timer fixture only. No installed
// service, production database, model, Docker, SSH or privileged operation.
if (process.argv.length !== 3 || process.argv[2] !== '--isolated' || process.platform !== 'darwin' || process.getuid() === 0)
  throw new Error('Usage: unprivileged node scripts/check-platform-watchdog.mjs --isolated');
const root = fileURLToPath(new URL('../', import.meta.url));
function run(executable, args, timeout = 120_000) {
  const result = spawnSync(executable, args, { cwd: root, encoding: 'utf8', timeout, maxBuffer: 1024 * 1024 });
  assert.equal(result.status, 0, 'Trusted watchdog fixture build failed');
  return result.stdout.trim();
}
run('swift', ['build', '--package-path', 'platform/studio']);
const built = run('swift', ['build', '--package-path', 'platform/studio', '--show-bin-path']);
const scratch = mkdtempSync('/tmp/fios009-watchdog-');
const bin = join(scratch, 'bin'), state = join(scratch, 'state');
mkdirSync(bin, { mode: 0o700 }); mkdirSync(state, { mode: 0o700 });
const lease = join(state, 'fixture.lease');
writeFileSync(lease, 'trusted-disposable-watchdog-fixture\n', { mode: 0o600, flag: 'wx' });
const children = [], seen = new Set();
function json(name) {
  try {
    const data = readFileSync(join(state, name));
    assert.ok(data.length <= 4096);
    return JSON.parse(data);
  } catch { return null; }
}
function alive(pid) { try { process.kill(pid, 0); return true; } catch { return false; } }
async function until(test, timeout = 40_000) {
  const deadline = performance.now() + timeout;
  while (performance.now() < deadline) {
    for (const name of ['progress.json']) { const row = json(name); if (row?.pid > 0) seen.add(row.pid); }
    const value = test(); if (value) return value;
    await delay(50);
  }
  throw new Error('Disposable watchdog acceptance deadline');
}
function start() {
  const child = spawn(join(bin, 'studio-supervisor'), ['--state', state], { stdio: 'ignore', env: { PATH: '/usr/bin:/bin', LANG: 'C' } });
  children.push(child); return child;
}
async function stop(child) {
  if (child.exitCode === null) child.kill('SIGTERM');
  await until(() => child.exitCode !== null || child.signalCode !== null, 5000);
}
try {
  copyFileSync(join(built, 'studio-supervisor'), join(bin, 'studio-supervisor'));
  chmodSync(join(bin, 'studio-supervisor'), 0o700);
  const source = join(scratch, 'WatchdogTimer.swift');
  copyFileSync(join(root, 'platform/studio/Tests/StudioCoreTests/WatchdogTimer.swift.fixture'), source);
  run('swiftc', ['-swift-version', '6', '-parse-as-library', '-warnings-as-errors', source, '-o', join(bin, 'studio-manager')]);
  chmodSync(join(bin, 'studio-manager'), 0o700);
  const firstSupervisor = start();
  const first = await until(() => {
    const value = json('progress.json'); return value?.beats >= 3 ? value : null;
  }, 10_000);
  assert.ok(first.heartbeat > first.progress);
  const fresher = await until(() => {
    const value = json('progress.json');
    return value?.pid === first.pid && value.beats >= first.beats + 5 ? value : null;
  }, 3000);
  assert.equal(fresher.progress, first.progress, 'Fixture loop progress must stay stalled');
  assert.ok(fresher.heartbeat > first.heartbeat, 'Independent timer must keep running');
  await until(() => {
    const status = json('supervisor.json');
    return status?.state === 'degraded' && status.starts === 3 && seen.size === 3 && [...seen].every(pid => !alive(pid));
  });
  const budget = json('restart-budget.json');
  assert.equal(budget.starts.length, 3);
  assert.ok(budget.starts.every((value, i) => i === 0 || value - budget.starts[i - 1] >= 10_000));
  await stop(firstSupervisor);
  const secondSupervisor = start();
  await until(() => {
    const status = json('supervisor.json');
    return status?.pid === secondSupervisor.pid && status.state === 'degraded' && status.starts === 3;
  }, 5000);
  await delay(1500);
  assert.deepEqual(json('restart-budget.json'), budget, 'Supervisor restart reset or spent an exhausted budget');
  assert.equal(seen.size, 3);
  assert.ok([...seen].every(pid => !alive(pid)), 'An exhausted budget launched a fourth manager');
  await stop(secondSupervisor);
  console.log('PASS: actual isolated supervisor rejects fresh timer-only heartbeat as loop progress; three finite spaced starts, child reap and exhausted budget survive supervisor restart. No native/boot/install acceptance.');
} finally {
  // Stop only our direct Process handles. Fixture children observe their own
  // private lease removal and also self-expire; never signal a reused PID.
  rmSync(lease, { force: true });
  for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
  await delay(1500);
  for (const child of children) if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  await delay(300);
  rmSync(scratch, { recursive: true, force: true });
}
