import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,rmSync,cpSync,chmodSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {validatePlatformRelease} from './lib/platform-release.mjs';

const args=process.argv.slice(2);
if(args.length!==9||args[0]!=='--isolated'||args[1]!=='--old'||args[3]!=='--old-sha256'||args[5]!=='--new'||args[7]!=='--new-sha256'||!args[2].startsWith('/')||!args[6].startsWith('/'))throw Error('Usage: node scripts/check-platform-upgrade.mjs --isolated --old ABS --old-sha256 REVIEWED_SHA --new ABS --new-sha256 REVIEWED_SHA');
assert.notEqual(args[4],args[8],'Recovery rehearsal requires distinct reviewed artifacts');
const oldRelease=resolve(args[2]),newRelease=resolve(args[6]);
for(const [path,digest] of [[oldRelease,args[4]],[newRelease,args[8]]]) {
  assert.ok(path.startsWith('/'));const verified=validatePlatformRelease(path,digest);
  assert.equal(verified.activation,false);assert.equal(verified.manifest.package_complete,false);
}
const root=resolve(import.meta.dirname,'..');
// Read before creating any state: missing fixture/invalid releases have no effects.
const fixture=readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/UpgradeLive.swift.fixture'));
const scratch=mkdtempSync('/tmp/fios009-upgrade-');chmodSync(scratch,0o700);
const state=join(scratch,'state'),helper=join(scratch,'upgrade-helper'),children=[];
function run(program,argv,timeout=5000) {
  const result=spawnSync(program,argv,{encoding:'utf8',timeout,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',HOME:process.env.HOME,LANG:'C',LC_ALL:'C'}});
  assert.equal(result.status,0,'Isolated artifact/schema command failed');return result.stdout.trim();
}
const cli=(release,directory,argv)=>JSON.parse(run(join(release,'bin/studioctl'),['--state',directory,...argv]));
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function stop(child) {
  if(exited(child))return;
  child.kill('SIGTERM');let until=Date.now()+2500;
  while(!exited(child)&&Date.now()<until)await delay(25);
  if(!exited(child)) {child.kill('SIGKILL');until=Date.now()+2000;while(!exited(child)&&Date.now()<until)await delay(25);}
  assert.ok(exited(child),'Unreaped fixture child: state must be retained');
}
async function cycle(release,directory) {
  const child=spawn(join(release,'bin/studio-manager'),['--state',directory],{stdio:'ignore',env:{PATH:'/usr/bin:/bin',HOME:process.env.HOME,LANG:'C',LC_ALL:'C'}});
  children.push(child);
  try {
    let status;const until=Date.now()+5000;
    while(!status&&Date.now()<until&&!exited(child)) {
      const result=spawnSync(join(release,'bin/studioctl'),['--state',directory,'status'],{encoding:'utf8',timeout:1000,maxBuffer:65536});
      if(result.status===0)status=JSON.parse(result.stdout);else await delay(50);
    }
    assert.equal(status?.ok,true);assert.equal(status.sandbox_admission,'disabled');
    const observation=cli(release,directory,['activity']).observation;
    assert.equal(observation.coverage,'unsupported');
    const exported=cli(newRelease,directory,['export']);
    assert.equal(exported.manager_epoch,observation.manager_epoch);assert.equal(exported.native_epoch,observation.native_epoch);
    assert.equal(exported.coverage,'unsupported');assert.equal('ok' in exported,false);
    const live=spawnSync(join(release,'bin/studioctl'),['--state',directory,'backup-state','--to',join(scratch,'live-backup-must-not-exist')],{stdio:'ignore',timeout:2000});
    assert.equal(live.status,1,'Backup accepted a live artifact manager');
  }finally {await stop(child);}
  assert.equal(JSON.parse(run(helper,['check',directory])).uncertain,1);
}
try {
  const source=join(scratch,'UpgradeLive.swift');
  writeFileSync(source,fixture);
  const found=run('/usr/bin/find',[join(root,'platform/studio/Sources/StudioCore'),'-name','*.swift']).split('\n').sort();
  run('/usr/bin/env',['swiftc','-O','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...found,source,'-o',helper],120000);
  run(helper,['seed',state]);
  await cycle(oldRelease,state);
  const bundle=join(scratch,'bundle');const backup=cli(oldRelease,state,['backup-state','--to',bundle]);
  assert.match(backup.sha256,/^[a-f0-9]{64}$/);
  await cycle(newRelease,state);await cycle(oldRelease,state);
  // New code independently verifies/consumes an old artifact's offline bundle.
  cli(newRelease,bundle,['verify-backup','--sha256',backup.sha256]);
  const restored=join(scratch,'restored');
  cli(newRelease,bundle,['restore-state','--sha256',backup.sha256,'--to',restored]);
  await cycle(newRelease,restored);await cycle(oldRelease,restored);
  const future=join(scratch,'future');cpSync(restored,future,{recursive:true});
  run(helper,['future',future]);
  const database=join(future,'state.sqlite');const digest=()=>createHash('sha256').update(readFileSync(database)).digest('hex');
  const before=digest();
  for(const release of [oldRelease,newRelease]) {
    const result=spawnSync(join(release,'bin/studio-manager'),['--state',future],{stdio:'ignore',timeout:3000});
    assert.equal(result.status,1,'Unknown ownership schema ran a manager');assert.equal(digest(),before,'Rejected ownership schema was mutated');
    const refused=spawnSync(join(release,'bin/studioctl'),['--state',future,'backup-state','--to',join(scratch,'future-backup-must-not-exist')],{stdio:'ignore',timeout:2000});
    assert.equal(refused.status,1);assert.equal(digest(),before);
  }
  console.log('PASS: verified old/new/old development artifacts, same-schema7 ownership/export preservation, stopped old backup→new verify/restore→old startup, future8 refusal without database mutation; disposable local state ONLY, no installed rollback/schema migration/native acceptance');
}finally {
  for(const child of children)await stop(child);
  if(children.every(exited))rmSync(scratch,{recursive:true,force:true});
  else throw Error('Fixture child not reaped; private state retained');
}
