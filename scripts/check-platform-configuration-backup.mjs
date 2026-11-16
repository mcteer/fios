import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,chmodSync,mkdirSync,readFileSync,writeFileSync,readdirSync,existsSync,lstatSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {validatePlatformRelease} from './lib/platform-release.mjs';

const args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
const release=resolve(args[2]),review=validatePlatformRelease(release,args[4]);
assert.equal(review.activation,false);
const root=resolve(import.meta.dirname,'..');
// Reuse the finite fixture's constrained namespace, actual journal and export.
// Retain all diagnostic data, including partial copies, on success or failure.
const scratch=mkdtempSync('/tmp/fios009-upgrade-configuration-');chmodSync(scratch,0o700);
const hash=data=>createHash('sha256').update(data).digest('hex');
function run(program,argv,{expected=0,timeout=10000}={}) {
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1) (allow default) (deny network*)',program,...argv],{encoding:'utf8',timeout,maxBuffer:1<<20});
  assert.equal(result.status,expected,'Finite network-denied configuration backup fixture failed; retained '+scratch);
  return result.stdout.trim();
}
try {
  const fixture=join(scratch,'UpgradeLive.swift'),helper=join(scratch,'state-fixture');
  writeFileSync(fixture,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/UpgradeLive.swift.fixture')),{mode:0o600});
  const sources=readdirSync(join(root,'platform/studio/Sources/StudioCore')).filter(name=>name.endsWith('.swift')).sort().map(name=>join(root,'platform/studio/Sources/StudioCore',name));
  const compile=spawnSync('/usr/bin/swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors','-j2','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,fixture,'-o',helper],{encoding:'utf8',timeout:300000,maxBuffer:1<<20});
  writeFileSync(join(scratch,'compile.log'),compile.stdout+compile.stderr,{mode:0o600});
  assert.equal(compile.status,0,'Fixture compile failed; retained '+scratch);
  const state=join(scratch,'state'),configuration=join(scratch,'configuration'),bundle=join(scratch,'bundle'),restored=join(scratch,'restored');
  run(helper,['seed',state]);mkdirSync(configuration,{mode:0o700});
  const opaque=Buffer.from('opaque invalid enrollment data; never authority');
  writeFileSync(join(configuration,'runtime-enrollment.json'),opaque,{mode:0o644});
  writeFileSync(join(configuration,'session-enrollment.json'),'',{mode:0o600});
  writeFileSync(join(configuration,'unrelated.json'),'retain separately',{mode:0o600});
  const cli=(directory,argv,options)=>run(join(release,'bin/studioctl'),['--state',directory,...argv],options);
  const proposalArgs=['--release',release,'--sha256',args[4],'--host','fios-edge-a.lab','--state',state,'--configuration',configuration,'--to',bundle];
  const proposal=JSON.parse(run(process.execPath,[join(root,'scripts/install-platform.mjs'),'plan-backup-config',...proposalArgs]));
  const uninstall=JSON.parse(run(process.execPath,[join(root,'scripts/install-platform.mjs'),'plan-uninstall-config',...proposalArgs]));
  assert.equal(existsSync(bundle),false,'Planning created a backup');
  assert.deepEqual(uninstall.proposed_commands[1],proposal.proposed_commands[0]);
  assert.equal(uninstall.state,'blocked');assert.deepEqual(uninstall.privileged_commands,[]);
  const command=proposal.proposed_commands[0];assert.equal(command.program,join(release,'bin/studioctl'));
  assert.equal(command.artifact_sha256,review.manifest.artifacts.find(item=>item.path==='bin/studioctl').sha256);
  const receipt=JSON.parse(run(command.program,command.arguments));
  assert.equal(receipt.ok,true);assert.equal(receipt.scope,'platform_journal_exports_and_configuration');
  assert.equal(receipt.installed,false);assert.equal(receipt.activation,false);
  const manifest=readFileSync(join(bundle,'backup.json'));
  assert.equal(hash(manifest),receipt.sha256);assert.equal(JSON.parse(manifest).version,4);
  assert.equal(JSON.parse(cli(bundle,['verify-backup','--sha256',receipt.sha256])).ok,true);
  const result=JSON.parse(cli(bundle,['restore-state','--sha256',receipt.sha256,'--to',restored]));
  assert.equal(result.started,false);assert.equal(result.installed,false);assert.equal(result.activation,false);
  assert.deepEqual(readFileSync(join(restored,'configuration/runtime-enrollment.json')),opaque);
  assert.equal(readFileSync(join(restored,'configuration/session-enrollment.json')).length,0);
  assert.equal(existsSync(join(restored,'configuration/python-enrollment.json')),false);
  assert.equal(existsSync(join(restored,'configuration/unrelated.json')),false);
  assert.equal(lstatSync(join(restored,'configuration/runtime-enrollment.json')).mode&0o7777,0o600);
  assert.equal(readFileSync(join(configuration,'unrelated.json'),'utf8'),'retain separately');
  assert.deepEqual(JSON.parse(run(helper,['check',restored])),{uncertain:1,exports:1});
  cli(state,['backup-state','--configuration',configuration,'--to',bundle],{expected:1});
  assert.equal(hash(readFileSync(join(bundle,'backup.json'))),receipt.sha256);
  const future=join(scratch,'future-state'),failedJournal=join(scratch,'failed-journal.sqlite');
  run(helper,['seed',future]);run(helper,['future',future]);
  assert.equal(cli(future,['backup','--to',failedJournal],{expected:1}),'');
  assert.equal(existsSync(failedJournal),true,'Rejected journal output was deleted');
  const index=JSON.parse(readFileSync(join(state,'artifacts/index.json')));
  const blob=index.records[0].id+'.blob',sourceBlob=join(state,'artifacts',blob),payload=readFileSync(sourceBlob);
  writeFileSync(sourceBlob,Buffer.alloc(payload.length));
  const failedExports=join(scratch,'failed-export-bundle');
  assert.equal(cli(state,['backup-state','--to',failedExports],{expected:1}),'');
  assert.deepEqual(readFileSync(join(failedExports,'artifacts',blob)),Buffer.alloc(payload.length));
  assert.equal(existsSync(join(failedExports,'backup.json')),false);
  assert.deepEqual(readFileSync(sourceBlob),Buffer.alloc(payload.length));
  writeFileSync(sourceBlob,payload);
  assert.deepEqual(JSON.parse(run(helper,['check',state])),{uncertain:1,exports:1});
  assert.equal(JSON.parse(cli(bundle,['verify-backup','--sha256',receipt.sha256])).ok,true);
  const final={scope:'isolated_packaged_cli_configuration_backup',manifest_sha256:args[4],source_revision:review.manifest.source_revision,configuration_plan_executed:true,uninstall_proposal_matches:true,backup_sha256:receipt.sha256,network:'denied',failed_journal_retained:true,failed_export_retained:true,model_posts:0,installed:false,activation:false,uncertainty:1,exports:1,scratch};
  writeFileSync(join(scratch,'receipt.json'),JSON.stringify(final,null,2)+'\n',{mode:0o600});
  console.log(JSON.stringify(final));
} catch(error) {
  console.error('Retained private configuration backup fixture: '+scratch);throw error;
}
