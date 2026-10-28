import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Local policy + private installed Pydantic child checks (MockTransport only).
// No SSH, daemon socket, service lifecycle or live inference. The test binary
// and descendants deny IP networking except one freshly allocated loopback
// mock endpoint; configured native ports/other IPs stay denied. No fallback.
if (![3,4].includes(process.argv.length) || process.argv[2] !== '--mock' || (process.argv.length===4 && process.argv[3]!=='--release')) {
  throw new Error('Usage: node scripts/check-platform.mjs --mock [--release]');
}
const root = fileURLToPath(new URL('../', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'fios-platform-policy-'));
try {
  const port = await new Promise((accept, reject) => {
    const listener = createServer();
    listener.once('error', reject);
    listener.listen({ host: '127.0.0.1', port: 0, exclusive: true }, () => {
      const value = listener.address().port;
      listener.close(error => error ? reject(error) : accept(value));
    });
  });
  if (!Number.isInteger(port) || port < 49152 || port > 65535) throw new Error('Mock endpoint outside private ephemeral range');
  // Seatbelt strips set-ID bits on chmod inside its child. Prepare a private
  // metadata-only fixture beforehand; it is NEVER launched (same UID owner).
  const setidFixture = join(directory, 'never-executed');
  copyFileSync('/usr/bin/true', setidFixture);
  chmodSync(setidFixture, 0o4700);
  const setidLockDirectory=join(directory,'setid-lock-state');
  mkdirSync(setidLockDirectory,{mode:0o700});
  const setidLock=join(setidLockDirectory,'manager.lock');
  copyFileSync('/usr/bin/true',setidLock);chmodSync(setidLock,0o4700);
  // A copied Apple platform binary is not a portable liveness witness.
  // Compile this exact portable, finite sentinel before
  // entering Seatbelt; the test requires an actual startup acknowledgement.
  const censusSource=join(directory,'CensusSentinel.swift'),censusBinary=join(directory,'census-sentinel');
  copyFileSync(resolve(root,'platform/studio/Tests/StudioCoreTests/CensusSentinel.swift.fixture'),censusSource);
  const censusBuild=spawnSync('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-O',censusSource,'-o',censusBinary],{cwd:root,stdio:'inherit',timeout:30000});
  if(censusBuild.error)throw censusBuild.error;
  if(censusBuild.status!==0)throw Error('Portable census fixture build failed');
  const sources = ['Sources/StudioCore', 'Tests/StudioCoreTests'].flatMap(part => {
    const path = resolve(root, 'platform/studio', part);
    return readdirSync(path).filter(name => name.endsWith('.swift')).sort().map(name => join(path, name));
  });
  const binary = join(directory, 'policy-tests');
  for (const [command, args] of [
    ['swiftc', ['-swift-version', '6', '-warnings-as-errors', ...(process.argv[3]==='--release'?['-O']:[]), '-I', resolve(root, 'platform/studio/Sources/CSQLite'), ...sources, '-o', binary]],
    ['/usr/bin/sandbox-exec', ['-D', `FIOS_MOCK_ENDPOINT=localhost:${port}`, '-f', resolve(root, 'tests/fixtures/platform/mock-network.sb'), binary]],
  ]) {
    const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', timeout: 120_000, env: { ...process.env, FIOS_PLATFORM_MOCK_PORT: String(port), FIOS_PLATFORM_SETID_FIXTURE: setidFixture, FIOS_PLATFORM_LOCK_SETID_FIXTURE: setidLock, FIOS_PLATFORM_CENSUS_FIXTURE:censusBinary } });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Platform policy validation failed (${result.status ?? result.signal})`);
  }
} finally {
  rmSync(directory, { recursive: true, force: true });
}
