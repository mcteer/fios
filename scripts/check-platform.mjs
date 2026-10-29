import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createServer } from 'node:net';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Explicit isolated acceptance measurements. The runtime exerciser creates
// only finite owned test containers on the existing local runtime; no native
// service lifecycle, production state, model request or installation occurs.
if(process.argv.length===3&&process.argv[2]==='--isolated-metrics'){
  const measurementRoot=fileURLToPath(new URL('../',import.meta.url));
  for(const [script,...args] of [
    ['scripts/check-platform-idle.mjs','--isolated','300'],
    ['scripts/check-platform-sandbox.mjs','--isolated','--resource-limits'],
    ['scripts/check-platform-watchdog.mjs','--isolated'],
  ]){
    const result=spawnSync(process.execPath,[resolve(measurementRoot,script),...args],{cwd:measurementRoot,stdio:'inherit',timeout:900000});
    if(result.error||result.status!==0)throw Error('Isolated measurement failed; retain uncertain fixture state and inspect its diagnostics');
  }
  process.exit(0);
}

// Local policy + private installed Pydantic child checks (MockTransport only).
// No SSH, daemon socket, service lifecycle or live inference. The test binary
// and descendants deny IP networking except one freshly allocated loopback
// mock endpoint; configured native ports/other IPs stay denied. No fallback.
if (![3,4].includes(process.argv.length) || process.argv[2] !== '--mock' || (process.argv.length===4 && !['--release','--mutate-runtime-postcheck','--mutate-manager-epoch','--mutate-activity-coverage','--mutate-inference-scope','--mutate-observation-native-sequence','--mutate-resource-freshness','--mutate-vm-profile-rebind','--mutate-vm-running-gate','--mutate-service-census','--mutate-lineage-unknown','--mutate-lineage-root','--mutate-launch-hold','--mutate-worker-start-inline','--mutate-worker-rss-read','--mutate-drain-epoch-normalization','--mutate-worker-kill-grace','--mutate-sandbox-epoch-normalization','--mutate-service-intent','--mutate-broker-service-intent','--mutate-worker-reap-publication','--mutate-drain-maintenance-order','--mutate-drain-local-ledger','--mutate-drain-uncertainty-count'].includes(process.argv[3]))) {
  throw new Error('Usage: node scripts/check-platform.mjs --isolated-metrics | --mock [--release|--mutate-runtime-postcheck|--mutate-manager-epoch|--mutate-activity-coverage|--mutate-inference-scope|--mutate-observation-native-sequence|--mutate-resource-freshness|--mutate-vm-profile-rebind|--mutate-vm-running-gate|--mutate-service-census|--mutate-lineage-unknown|--mutate-lineage-root|--mutate-launch-hold|--mutate-worker-start-inline|--mutate-worker-rss-read|--mutate-drain-epoch-normalization|--mutate-worker-kill-grace|--mutate-sandbox-epoch-normalization|--mutate-service-intent|--mutate-broker-service-intent|--mutate-worker-reap-publication|--mutate-drain-maintenance-order|--mutate-drain-local-ledger|--mutate-drain-uncertainty-count]');
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
  const vmStatusSource=join(directory,'VMRunningCLI.swift'),vmStatusBinary=join(directory,'vm-running-cli');
  copyFileSync(resolve(root,'platform/studio/Tests/StudioCoreTests/VMRunningCLI.swift.fixture'),vmStatusSource);
  const vmStatusBuild=spawnSync('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-O',vmStatusSource,'-o',vmStatusBinary],{cwd:root,stdio:'inherit',timeout:30000});
  if(vmStatusBuild.error)throw vmStatusBuild.error;
  if(vmStatusBuild.status!==0)throw Error('Finite VM status fixture build failed');
  const rssSource=join(directory,'WorkerRSSSentinel.swift'),rssBinary=join(directory,'worker-rss-sentinel');
  copyFileSync(resolve(root,'platform/studio/Tests/StudioCoreTests/WorkerRSSSentinel.swift.fixture'),rssSource);
  const rssBuild=spawnSync('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-O',rssSource,'-o',rssBinary],{cwd:root,stdio:'inherit',timeout:30000});
  if(rssBuild.error)throw rssBuild.error;
  if(rssBuild.status!==0)throw Error('Finite RSS fixture build failed');
  const sources = ['Sources/StudioCore', 'Tests/StudioCoreTests'].flatMap(part => {
    const path = resolve(root, 'platform/studio', part);
    return readdirSync(path).filter(name => name.endsWith('.swift')).sort().map(name => {
      const source=join(path,name);
      const variant=process.argv[3]==='--mutate-runtime-postcheck'?{file:'Sandboxes.swift',check:'        try pinned?.verify(deadline:min(deadline,ProcessInfo.processInfo.systemUptime+2))',replacement:'        withExtendedLifetime(pinned) {}'}:
        process.argv[3]==='--mutate-worker-reap-publication'?{file:'PrivateWorker.swift',check:'            try journal.recordWorkerGone(job:job,attempt:attempt,grant:grant)\n            reaped=true',replacement:'            reaped=true\n            try journal.recordWorkerGone(job:job,attempt:attempt,grant:grant)'}:
        process.argv[3]==='--mutate-drain-maintenance-order'?{file:'ServiceDrainController.swift',check:'        try journal.setDesired(service:service.rawValue,desired:ServiceDesired.maintenance.rawValue)\n        let progress=try policy.begin(snapshot:snapshot,role:role,now:now)\n        reports[service]=progress;originalOwned[service]=Set(snapshot.scope.ownedJobs)\n        try revoke(progress,now:now,uptime:uptime)',replacement:'        let progress=try policy.begin(snapshot:snapshot,role:role,now:now)\n        reports[service]=progress;originalOwned[service]=Set(snapshot.scope.ownedJobs)\n        try revoke(progress,now:now,uptime:uptime)\n        try journal.setDesired(service:service.rawValue,desired:ServiceDesired.maintenance.rawValue)'}:
        process.argv[3]==='--mutate-drain-local-ledger'?{file:'ServiceDrainController.swift',check:'remaining.isSubset(of:Set(value.scope.ownedJobs))',replacement:'remaining.isSubset(of:remaining)'}:
        process.argv[3]==='--mutate-drain-uncertainty-count'?{file:'ServiceDrainController.swift',check:'value.scope.unresolvedManagedRequests.count == (try journal.unresolvedCount())',replacement:'value.scope.unresolvedManagedRequests.count>=0'}:
        process.argv[3]==='--mutate-service-intent'?{file:'ServiceAdmission.swift',check:'if model,try journal.desired(service:ManagedService.mlx.rawValue)',replacement:'if model && sandbox,try journal.desired(service:ManagedService.mlx.rawValue)'}:
        process.argv[3]==='--mutate-broker-service-intent'?{file:'ModelBroker.swift',check:'        guard try ServiceAdmissionPolicy.permits(journal:journal,model:true,sandbox:false) else {throw AdmissionError.capacity}',replacement:''}:
        process.argv[3]==='--mutate-sandbox-epoch-normalization'?{file:'TaskController.swift',check:'ModelBroker.scopeIdentity(a)==ModelBroker.scopeIdentity(b)',replacement:'a.host==b.host && a.profileHash==b.profileHash && a.managerEpoch==b.managerEpoch && WireScalar.exactModel(a.canonicalModel,b.canonicalModel) && WireScalar.exactModel(a.nativeModel,b.nativeModel) && a.nativeSnapshot.endpointHash==b.nativeSnapshot.endpointHash && a.nativeSnapshot.nativeEpoch==b.nativeSnapshot.nativeEpoch'}:
        process.argv[3]==='--mutate-worker-kill-grace'?{file:'PrivateWorker.swift',check:'now-cancelAt>=500',replacement:'now-cancelAt>=1000'}:
        process.argv[3]==='--mutate-drain-epoch-normalization'?{file:'Drain.swift',check:'record.nativeEpoch.map({Data($0.utf8)}) != scope.nativeEpoch.map({Data($0.utf8)})',replacement:'record.nativeEpoch != scope.nativeEpoch'}:
        process.argv[3]==='--mutate-worker-rss-read'?{file:'PrivateWorker.swift',check:'let resident=try? WorkerResources.residentBytes(pid:process.processIdentifier)',replacement:'let resident:UInt64?=1'}:
        process.argv[3]==='--mutate-worker-start-inline'?{file:'AsyncWorkerStart.swift',check:'Thread.detachNewThread { [self] in\n            let value=work { [self] in lock.lock();defer {lock.unlock()};return cancelled }\n            lock.lock();result=value;lock.unlock()\n        }',replacement:'let value=work { [self] in lock.lock();defer {lock.unlock()};return cancelled };result=value'}:
        process.argv[3]==='--mutate-launch-hold'?{file:'ModelBroker.swift',check:'for key in held where try journal.workerLaunchReaped(job:key.job,attempt:key.attempt)',replacement:'for key in held'}:
        process.argv[3]==='--mutate-manager-epoch'?{file:'ManagerExecution.swift',check:'value.managerEpoch==managerEpoch,',replacement:''}:
        process.argv[3]==='--mutate-activity-coverage'?{file:'NativeActivityCoherence.swift',check:'sourceCoverage == .all_clients && coverage == .all_clients',replacement:'coverage == .all_clients'}:
        process.argv[3]==='--mutate-inference-scope'?{file:'Journal.swift',check:'try record.scope.encoded()==scope.encoded()',replacement:'true'}:
        process.argv[3]==='--mutate-lineage-root'?{file:'NativeRequestLineage.swift',check:'if let original=rootSequence,original != value.rootSequence',replacement:'if let original=rootSequence,original == 0'}:
        process.argv[3]==='--mutate-lineage-unknown'?{file:'NativeRequestLineage.swift',check:'uncertain && rootSequence==0 && references==0 && owners==0',replacement:'rootSequence==0 && references==0 && owners==0'}:
        process.argv[3]==='--mutate-service-census'?{file:'ServiceProcessCensus.swift',check:'Set(second)==Set(first),',replacement:''}:
        process.argv[3]==='--mutate-vm-running-gate'?{file:'VMRunning.swift',check:'            let proof=try running.capture(),before=now()',replacement:'            let proof=VMRunningProof(sourceSHA256:expectedCLIHash,sampledAt:stamp),before=now()'}:
        process.argv[3]==='--mutate-vm-profile-rebind'?{file:'VMResourceProfileReader.swift',check:'        let result=try bound!.read(configuration:configuration,id:id,leaseUntil:leaseUntil)',replacement:'        let result:VMKernelSample\n        do {result=try bound!.read(configuration:configuration,id:id,leaseUntil:leaseUntil)}\n        catch RuntimeError.launch {bound=nil;throw RuntimeError.launch}'}:
        process.argv[3]==='--mutate-resource-freshness'?{file:'ResourceObservation.swift',check:'fresh ? "observed":"stale"',replacement:'(fresh || !fresh) ? "observed":"stale"'}:
        process.argv[3]==='--mutate-observation-native-sequence'?{file:'ObservationExport.swift',check:'counter>nativeSequence',replacement:'counter>=nativeSequence'}:undefined;
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
    const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', timeout: command==='swiftc'?300_000:120_000, env: { ...process.env, FIOS_PLATFORM_MOCK_PORT: String(port), FIOS_PLATFORM_SETID_FIXTURE: setidFixture, FIOS_PLATFORM_LOCK_SETID_FIXTURE: setidLock, FIOS_PLATFORM_CENSUS_FIXTURE:censusBinary, FIOS_PLATFORM_ENDPOINT_FIXTURE:endpointBinary, FIOS_PLATFORM_VM_STATUS_FIXTURE:vmStatusBinary, FIOS_PLATFORM_RSS_FIXTURE:rssBinary } });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`Platform policy validation failed (${result.status ?? result.signal})`);
  }
} finally {
  rmSync(directory, { recursive: true, force: true });
}
