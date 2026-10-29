import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Local policy + private installed Pydantic child checks (MockTransport only).
// No SSH, daemon socket, service lifecycle or live inference. The test binary
// and descendants deny IP networking except one freshly allocated loopback
// mock endpoint; configured native ports/other IPs stay denied. No fallback.
if (![3,4].includes(process.argv.length) || process.argv[2] !== '--mock' || (process.argv.length===4 && !['--release','--mutate-runtime-postcheck','--mutate-manager-epoch','--mutate-activity-coverage','--mutate-inference-scope'].includes(process.argv[3]))) {
  throw new Error('Usage: node scripts/check-platform.mjs --mock [--release|--mutate-runtime-postcheck|--mutate-manager-epoch|--mutate-activity-coverage|--mutate-inference-scope]');
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
  const endpointSource=join(directory,'EndpointCommand.swift'),endpointBinary=join(directory,'runtime-endpoint-command');
  copyFileSync(resolve(root,'platform/studio/Tests/StudioCoreTests/RuntimeEndpointCommand.swift.fixture'),endpointSource);
  const endpointBuild=spawnSync('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-O',endpointSource,'-o',endpointBinary],{cwd:root,stdio:'inherit',timeout:30000});
  if(endpointBuild.error)throw endpointBuild.error;
  if(endpointBuild.status!==0)throw Error('Finite endpoint fixture build failed');
  const sources = ['Sources/StudioCore', 'Tests/StudioCoreTests'].flatMap(part => {
    const path = resolve(root, 'platform/studio', part);
    return readdirSync(path).filter(name => name.endsWith('.swift')).sort().map(name => {
      const source=join(path,name);
      const variant=process.argv[3]==='--mutate-runtime-postcheck'?{file:'Sandboxes.swift',check:'        try pinned?.verify(deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))',replacement:'        withExtendedLifetime(pinned) {}'}:
        process.argv[3]==='--mutate-manager-epoch'?{file:'ManagerExecution.swift',check:'value.managerEpoch==managerEpoch,',replacement:''}:
        process.argv[3]==='--mutate-activity-coverage'?{file:'NativeActivityCoherence.swift',check:'sourceCoverage == .all_clients && coverage == .all_clients',replacement:'coverage == .all_clients'}:
        process.argv[3]==='--mutate-inference-scope'?{file:'Journal.swift',check:'try record.scope.encoded()==scope.encoded()',replacement:'true'}:undefined;
      if(!variant||part!=='Sources/StudioCore'||name!==variant.file)return source;
      const original=readFileSync(source,'utf8');
      if(original.split(variant.check).length!==2)throw Error('Private mutation boundary changed');
      const mutated=join(directory,'Mutated'+name);writeFileSync(mutated,original.replace(variant.check,variant.replacement));return mutated;
    });
  });
  const binary = join(directory, 'policy-tests');
  for (const [command, args] of [
    ['swiftc', ['-swift-version', '6', '-warnings-as-errors', ...(process.argv[3]==='--release'?['-O']:[]), '-I', resolve(root, 'platform/studio/Sources/CSQLite'), ...sources, '-o', binary]],
    ['/usr/bin/sandbox-exec', ['-D', `FIOS_MOCK_ENDPOINT=localhost:${port}`, '-f', resolve(root, 'tests/fixtures/platform/mock-network.sb'), binary]],
  ]) {
    // Compilation has its own finite hosted-runner allowance. Runtime tests
    // retain120s; no model, IPC, native-command or cleanup deadline is raised.
    const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', timeout: command==='swiftc'?300_000:120_000, env: { ...process.env, FIOS_PLATFORM_MOCK_PORT: String(port), FIOS_PLATFORM_SETID_FIXTURE: setidFixture, FIOS_PLATFORM_LOCK_SETID_FIXTURE: setidLock, FIOS_PLATFORM_CENSUS_FIXTURE:censusBinary, FIOS_PLATFORM_ENDPOINT_FIXTURE:endpointBinary } });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Platform policy validation failed (${result.status ?? result.signal})`);
  }
} finally {
  rmSync(directory, { recursive: true, force: true });
}
