#!/usr/bin/env node
// Trusted-host, finite isolated rehearsal. No daemon restart, pull, native
// service/inference action, production database, source mount or global prune.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,copyFileSync,chmodSync,realpathSync,rmSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import assert from 'node:assert/strict';
assert.deepEqual(process.argv.slice(2),['--isolated'],'Use --isolated for the trusted-host rehearsal');
const root=resolve(import.meta.dirname,'..');
function run(command,args,{cwd=root,timeout=120000}={}) {
 const result=spawnSync(command,args,{cwd,encoding:'utf8',timeout,maxBuffer:1<<20,env:{PATH:process.env.PATH,HOME:process.env.HOME,LANG:'C',LC_ALL:'C'}});
 if(result.status!==0)throw Error(`Finite rehearsal subprocess failed (${result.status??result.signal}): ${result.stderr??''}`);
 return result.stdout.trim();
}
// Keep real isolation/cgroup measurements separate from restart/transport-loss
// evidence; this child owns and verifies removal of its own finite resources.
console.log(run(process.execPath,[join(root,'scripts/check-platform-sandbox.mjs'),'--isolated','--isolation-matrix'],{timeout:240000}));
const directory=mkdtempSync(join(tmpdir(),'fios-platform-container-')),docker=join(directory,'docker');
const job=randomUUID(),nonce=randomBytes(32).toString('hex'),volume='fios-rehearsal-sentinel-'+randomUUID();
let socketURL,image,sentinel,createdID,volumeBefore,possible=false,verified=false;
const runtime=args=>run(docker,['--host',socketURL,...args]);
function receipt(value){writeFileSync(join(directory,'fixture-receipt.json'),JSON.stringify({version:1,job,nonce,image,sentinel,volume,created_id:createdID,...value},null,2)+'\n',{mode:0o600});}
try {
 copyFileSync(realpathSync(run('/usr/bin/which',['docker'])),docker);chmodSync(docker,0o700);
 socketURL=run(docker,['context','inspect','--format','{{.Endpoints.docker.Host}}']);assert.match(socketURL,/^unix:\/\/\//);
 image=runtime(['image','inspect','fios:current','--format','{{.Id}}']);assert.match(image,/^sha256:[a-f0-9]{64}$/);
 const source=join(directory,'ContainerRecoveryLive.swift'),binary=join(directory,'container-recovery');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ContainerRecoveryLive.swift.fixture'),source);
 const core=join(root,'platform/studio/Sources/StudioCore');
 run('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),source,'-o',binary]);
 const digest=createHash('sha256').update(readFileSync(docker)).digest('hex');
 receipt({phase:'before-volume-create'});possible=true;
 assert.equal(runtime(['volume','create','--label','lab.fios.fixture.owner='+nonce,volume]),volume);
 volumeBefore=runtime(['volume','inspect','--format','{{json .}}',volume]);
 const inspectedVolume=JSON.parse(volumeBefore);
 assert.equal(inspectedVolume.Name,volume);assert.equal(inspectedVolume.Driver,'local');assert.equal(inspectedVolume.Labels?.['lab.fios.fixture.owner'],nonce);
 receipt({phase:'before-sentinel-create'});

 sentinel=runtime(['create','--name','fios-recovery-sentinel-'+randomUUID(),'--pull=never','--network=none','--read-only','--user=65532:65532','--cap-drop=ALL','--security-opt=no-new-privileges:true','--memory=67108864','--memory-swap=67108864','--cpus=1','--pids-limit=16','--log-driver=none',image]);assert.match(sentinel,/^[a-f0-9]{64}$/);
 const before=runtime(['inspect','--format','{{json .}}',sentinel]);
 const state=join(directory,'state'),started=performance.now();
 for(const phase of ['create-lost','recover-create','recover-remove']) {
  receipt({phase});const output=run(binary,[phase,state,docker,digest,socketURL.slice(7),image,nonce,job],{timeout:30000});
  if(phase==='create-lost'){const created=JSON.parse(output);assert.match(created.created_id,/^[a-f0-9]{64}$/);createdID=created.created_id;receipt({phase,created});}
  console.log(output);
  assert.equal(runtime(['inspect','--format','{{json .}}',sentinel]),before,'Unrelated sentinel changed');
  assert.equal(runtime(['volume','inspect','--format','{{json .}}',volume]),volumeBefore,'Unrelated sentinel volume changed');
 }
 const elapsed=Math.round(performance.now()-started);assert(elapsed<=60000,'Recovery cleanup exceeded60s');
 assert.equal(runtime(['ps','--all','--no-trunc','--filter','name=^/fios-sandbox-'+job+'$','--format','{{.ID}}']),'');
 console.log(`METRIC: actual process restart/adoption/removal recovery_ms=${elapsed} native_uncertain=1 sentinel_unchanged=true volume_unchanged=true; absent endpoint is injected, daemon not restarted`);
 verified=true;
}finally {
 if(verified){
  try {assert.equal(runtime(['inspect','--format','{{.Id}}',sentinel]),sentinel);runtime(['rm',sentinel]);assert.equal(runtime(['ps','--all','--no-trunc','--filter','id='+sentinel,'--format','{{.ID}}']),'');assert.equal(runtime(['volume','inspect','--format','{{json .}}',volume]),volumeBefore);runtime(['volume','rm',volume]);rmSync(directory,{recursive:true,force:true});}
  catch(error){console.error('RETAINED: incomplete owned sentinel cleanup: '+directory);throw error;}
 }else if(possible){console.error('RETAINED: uncertain container rehearsal; no parent cleanup attempted: '+directory);}
 else rmSync(directory,{recursive:true,force:true});
}
