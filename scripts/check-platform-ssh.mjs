#!/usr/bin/env node
// Disposable loopback-only OpenSSH authentication/export fixture. Does not read
// or modify host sshd config, authorized_keys, agents, identities or known_hosts.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { userInfo, homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2), ['--isolated']);
assert.equal(process.getuid(), process.geteuid());
assert.notEqual(process.getuid(), 0, 'fixture must be unprivileged');
const root = fileURLToPath(new URL('../', import.meta.url));
// StrictModes rejects world-writable /tmp ancestors even when the leaf is
// private. Use a fresh private leaf under the current user's home, never .ssh.
const scratch = mkdtempSync(join(homedir(), '.fios-ssh-fixture-')), children = [];
const username = userInfo().username;
assert.match(username, /^[a-z_][a-z0-9_-]{0,31}$/);
const run = (exe, argv, options = {}) => spawnSync(exe, argv, { encoding: 'utf8', timeout: 10_000, maxBuffer: 128 * 1024, ...options });
const ok = (exe, argv, options) => { const r = run(exe, argv, options); assert.equal(r.status, 0, `fixed fixture step failed: ${exe}`); return r.stdout; };
async function port() {
  const server = createServer();
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const value = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return value;
}
async function exited(child, milliseconds = 5000) {
  const end = Date.now() + milliseconds;
  while (child.exitCode === null && child.signalCode === null && Date.now() < end) await delay(25);
  assert(child.exitCode !== null || child.signalCode !== null, 'owned fixture process did not exit');
}
function refused(result, reason) {
  assert.equal(result.error, undefined, `${reason}: transport failure/timeout is not refusal evidence`);
  assert.equal(result.signal, null, `${reason}: killed transport is not refusal evidence`);
  assert(Number.isInteger(result.status) && result.status > 0, reason);
}
// Prevent false greens when an accepted -N forwarding session merely times out.
assert.throws(() => refused({ status: null, signal: 'SIGTERM', error: new Error('fixture timeout') }, 'timeout'));
assert.throws(() => refused({ status: 0, signal: null }, 'success'));
let target, forwarded = 0;
try {
  ok('swift', ['build', '--package-path', 'platform/studio'], { cwd: root, timeout: 120_000 });
  const bin = ok('swift', ['build', '--package-path', 'platform/studio', '--show-bin-path'], { cwd: root, timeout: 30_000 }).trim();
  const cli = join(bin, 'studioctl'), state = join(scratch, 'state');
  for (const value of [cli, state]) assert.match(value, /^\/[a-zA-Z0-9_./-]+$/, 'forced command paths must require no shell substitution');
  mkdirSync(state, { mode: 0o700 });
  const manager = spawn(join(bin, 'studio-manager'), ['--state', state], { stdio: 'ignore' });
  children.push(manager);
  const deadline = Date.now() + 10_000;
  let local;
  while (Date.now() < deadline) {
    const r = run(cli, ['--state', state, 'export'], { timeout: 1500 });
    if (r.status === 0) { local = JSON.parse(r.stdout); break; }
    await delay(50);
  }
  assert(local, 'disposable manager did not become observable');
  assert.equal(local.coverage, 'unsupported');
  // Keys are generated only inside the private disposable directory. No key,
  // passphrase, workload or daemon log is emitted by this fixture.
  const hostkey = join(scratch, 'host'), identity = join(scratch, 'client');
  for (const key of [hostkey, identity]) ok('/usr/bin/ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-f', key]);
  const publicKey = file => {
    const text = readFileSync(file + '.pub', 'utf8').trim();
    assert.match(text, /^ssh-ed25519 [A-Za-z0-9+/=]+(?: [^\r\n]+)?$/);
    return text.split(' ').slice(0, 2).join(' ');
  };
  const authorized = join(scratch, 'authorized_keys'), config = join(scratch, 'sshd_config');
  const command = `${cli} --state ${state} export`;
  writeFileSync(authorized, `restrict,command="${command}" ${publicKey(identity)}\n`, { mode: 0o600 });
  const listen = await port();
  writeFileSync(config, [
    `Port ${listen}`, 'AddressFamily inet', 'ListenAddress 127.0.0.1', `HostKey ${hostkey}`,
    `PidFile ${join(scratch, 'sshd.pid')}`, `AuthorizedKeysFile ${authorized}`, `AllowUsers ${username}`,
    'PubkeyAuthentication yes', 'AuthenticationMethods publickey', 'PasswordAuthentication no',
    'KbdInteractiveAuthentication no', 'HostbasedAuthentication no', 'UsePAM no', 'PermitRootLogin no',
    'StrictModes yes', 'PermitUserEnvironment no', 'PermitUserRC no', 'PermitTTY no',
    'DisableForwarding yes', 'AllowTcpForwarding no', 'AllowStreamLocalForwarding no',
    'AllowAgentForwarding no', 'X11Forwarding no', 'PermitTunnel no', 'PermitOpen none', 'PermitListen none',
    'MaxAuthTries 2', 'MaxSessions 1', 'LoginGraceTime 5', 'LogLevel ERROR',
    `ForceCommand ${command}`, 'SetEnv PATH=/usr/bin:/bin', '',
  ].join('\n'), { mode: 0o600 });
  const effective = ok('/usr/sbin/sshd', ['-T', '-f', config, '-C', `user=${username},host=localhost,addr=127.0.0.1,laddr=127.0.0.1,lport=${listen}`]);
  for (const policy of ['disableforwarding yes', 'allowtcpforwarding no', 'allowstreamlocalforwarding no',
    'allowagentforwarding no', 'x11forwarding no', 'permittunnel no', 'permittty no', 'permituserrc no',
    'permituserenvironment no', 'passwordauthentication no', 'kbdinteractiveauthentication no',
    'hostbasedauthentication no', 'usepam no', 'permitopen none', 'permitlisten none']) {
    assert(effective.split('\n').includes(policy), `effective policy mismatch: ${policy}`);
  }
  assert(!/^acceptenv\s+\S/m.test(effective), 'server accepts caller environment');
  assert(effective.includes(`forcecommand ${command}\n`));
  assert(effective.includes(`authorizedkeysfile ${authorized}\n`));
  const daemon = spawn('/usr/sbin/sshd', ['-D', '-e', '-f', config], { stdio: ['ignore', 'ignore', 'pipe'] });
  children.push(daemon);
  // Keep bounded diagnostics private; they can contain account/key metadata.
  let daemonError = '';
  daemon.stderr.on('data', chunk => { if (daemonError.length < 16384) daemonError += chunk.toString().slice(0, 16384 - daemonError.length); });
  const known = join(scratch, 'known_hosts'), wrongKnown = join(scratch, 'wrong_known_hosts');
  writeFileSync(known, `[127.0.0.1]:${listen} ${publicKey(hostkey)}\n`, { mode: 0o600 });
  writeFileSync(wrongKnown, `[127.0.0.1]:${listen} ${publicKey(identity)}\n`, { mode: 0o600 });
  const base = ['-F', '/dev/null', '-p', String(listen), '-i', identity, '-o', 'IdentitiesOnly=yes',
    '-o', 'IdentityAgent=none', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
    '-o', `UserKnownHostsFile=${known}`, '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'UpdateHostKeys=no',
    '-o', 'ConnectTimeout=2', '-o', 'ConnectionAttempts=1', '-o', 'LogLevel=ERROR'];
  const address = `${username}@127.0.0.1`;
  const ssh = (extra = [], command = [], options = {}) => run('/usr/bin/ssh', [...base, ...extra, address, ...command], { input: '', ...options });
  let remote;
  const ready = Date.now() + 8000;
  while (Date.now() < ready) {
    const r = ssh(['-T']);
    if (r.status === 0) { remote = JSON.parse(r.stdout); break; }
    if (daemon.exitCode !== null || daemon.signalCode !== null) break;
    await delay(100);
  }
  assert(remote, 'isolated SSH export failed (private daemon diagnostics retained only in memory)');
  assert.equal(remote.manager_epoch, local.manager_epoch); assert.equal(remote.native_epoch, local.native_epoch);
  assert.equal(remote.coverage, 'unsupported'); assert.equal(remote.outstanding_owners, null);
  assert.equal('ok' in remote, false); assert(Buffer.byteLength(JSON.stringify(remote)) <= 65536);
  for (const remoteCommand of [['service.force mlx'], ['export']]) {
    const r = ssh(['-T'], remoteCommand);
    refused(r, 'forced exporter interpreted an alternate remote command');
    assert.equal(r.stdout, '');
  }
  const subsystem = ssh(['-T', '-s'], ['sftp']);
  refused(subsystem, 'subsystem command accepted'); assert.equal(subsystem.stdout, '');
  const pty = ssh(['-tt']);
  refused(pty, 'PTY request was not refused');
  assert.equal(pty.stdout, '');
  const wrongHost = base.map(value => value === `UserKnownHostsFile=${known}` ? `UserKnownHostsFile=${wrongKnown}` : value);
  refused(run('/usr/bin/ssh', [...wrongHost, '-T', address], { input: '' }), 'wrong server host key accepted');
  const wrongClient = base.map(value => value === identity ? hostkey : value);
  refused(run('/usr/bin/ssh', [...wrongClient, '-T', address], { input: '' }), 'foreign client identity accepted');
  // A private target witnesses whether a forbidden forwarding channel opens.
  target = createServer(socket => { forwarded += 1; socket.destroy(); });
  await new Promise(resolve => target.listen(0, '127.0.0.1', resolve));
  const targetPort = target.address().port;
  const forward = ssh(['-T', '-W', `127.0.0.1:${targetPort}`]);
  refused(forward, 'direct TCP forwarding accepted');
  const reverse = ssh(['-N', '-o', 'ExitOnForwardFailure=yes', '-R', `127.0.0.1:0:127.0.0.1:${targetPort}`]);
  refused(reverse, 'reverse TCP forwarding accepted');
  const stream = ssh(['-N', '-o', 'ExitOnForwardFailure=yes', '-R', `${join(scratch, 'forward.sock')}:127.0.0.1:${targetPort}`]);
  refused(stream, 'Unix forwarding accepted');
  await delay(50); assert.equal(forwarded, 0);
  const injected = ssh(['-T'], [], { input: '{"operation":"service.force"}\n' });
  assert.equal(injected.status, 0); assert.equal(JSON.parse(injected.stdout).coverage, 'unsupported');
  assert.equal(JSON.parse(ok(cli, ['--state', state, 'status'])).services.mlx.desired, 'running');
  assert.equal(manager.exitCode, null); assert.equal(daemon.exitCode, null);
  console.log('PASS: real isolated OpenSSH public-key/host-key authenticated raw export; effective environment/PTY/RC/forwarding restrictions; alternate command/subsystem/foreign-key/forwarding refusals; manager unchanged.');
  console.log('Disposable loopback fixture only: no host SSH enrollment/configuration or native serving activation.');
} finally {
  if (target) await new Promise(resolve => target.close(resolve));
  for (const child of children.reverse()) {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    try { await exited(child, 2000); } catch { child.kill('SIGKILL'); await exited(child); }
  }
  rmSync(scratch, { recursive: true, force: true });
}
