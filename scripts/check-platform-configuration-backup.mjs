import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,chmodSync,mkdirSync,cpSync,readFileSync,writeFileSync,readdirSync,existsSync,lstatSync} from 'node:fs';
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
  const standalone=join(scratch,'journal-only.sqlite');
  const journalReceipt=JSON.parse(cli(state,['backup','--to',standalone]));
  const publishedJournal=readFileSync(standalone),publishedStat=lstatSync(standalone);
  assert.equal(journalReceipt.ok,true);assert.equal(journalReceipt.scope,'platform_journal_only');
  assert.equal(journalReceipt.schema,9);assert.equal(journalReceipt.bytes,publishedJournal.length);
  assert.equal(journalReceipt.sha256,hash(publishedJournal));
  cli(state,['backup','--to',standalone],{expected:1});
  assert.equal(lstatSync(standalone).ino,publishedStat.ino);
  assert.deepEqual(readFileSync(standalone),publishedJournal);
  for(const suffix of ['-wal','-shm','-journal']) {
    const refusedBase=join(scratch,`standalone-collision${suffix}.sqlite`);
    const sidecar=refusedBase+suffix;
    const original=Buffer.from(`unrelated private ${suffix} data`);
    writeFileSync(sidecar,original,{mode:0o600,flag:'wx'});
    const inode=lstatSync(sidecar).ino;
    cli(state,['backup','--to',refusedBase],{expected:1});
    assert(!existsSync(refusedBase),'Sidecar collision published a journal');
    assert.equal(lstatSync(sidecar).ino,inode);
    assert.deepEqual(readFileSync(sidecar),original);
  }
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
  const verified=JSON.parse(cli(bundle,['verify-backup','--sha256',receipt.sha256]));
  assert.equal(verified.journal_compatible,true);
  const result=JSON.parse(cli(bundle,['restore-state','--sha256',receipt.sha256,'--to',restored]));
  function assertStoppedReceipts(receipt,...projections){
   for(const projection of projections){
    assert.equal(projection.ok,true);
    assert.equal(projection.installed,false);assert.equal(projection.activation,false);
    for(const key of ['scope','bytes','artifacts','sha256'])assert.equal(projection[key],receipt[key],`Stopped receipt disagrees on ${key}`);
   }
  }
  assertStoppedReceipts(receipt,verified,result);
  assert.equal(result.started,false);assert.equal(result.installed,false);assert.equal(result.activation,false);
  assert.deepEqual(readFileSync(join(restored,'configuration/runtime-enrollment.json')),opaque);
  assert.equal(readFileSync(join(restored,'configuration/session-enrollment.json')).length,0);
  assert.equal(existsSync(join(restored,'configuration/python-enrollment.json')),false);
  assert.equal(existsSync(join(restored,'configuration/unrelated.json')),false);
  assert.equal(lstatSync(join(restored,'configuration/runtime-enrollment.json')).mode&0o7777,0o600);
  assert.equal(readFileSync(join(configuration,'unrelated.json'),'utf8'),'retain separately');
  assert.deepEqual(JSON.parse(run(helper,['check',restored])),{uncertain:1,exports:1});
  const restoredDirectory=lstatSync(restored),restoredJournal=readFileSync(join(restored,'state.sqlite'));
  assert(restoredDirectory.isDirectory());assert.equal(restoredDirectory.mode&0o7777,0o700);
  cli(bundle,['restore-state','--sha256',receipt.sha256,'--to',restored],{expected:1});
  assert.equal(lstatSync(restored).ino,restoredDirectory.ino);
  assert.deepEqual(readFileSync(join(restored,'state.sqlite')),restoredJournal);
  cli(state,['backup-state','--configuration',configuration,'--to',bundle],{expected:1});
  assert.equal(hash(readFileSync(join(bundle,'backup.json'))),receipt.sha256);
  const pendingState=join(scratch,'pending-state'),pendingBackup=join(scratch,'pending-bundle'),pendingRestore=join(scratch,'pending-restored');
  run(helper,['seed',pendingState]);
  const pendingIndex=join(pendingState,'artifacts/index.json');
  const pending=JSON.parse(readFileSync(pendingIndex));
  assert.equal(pending.records.length,1);pending.records[0].state='pending';
  const pendingBytes=Buffer.from(JSON.stringify(pending));writeFileSync(pendingIndex,pendingBytes);
  const pendingReceipt=JSON.parse(cli(pendingState,['backup-state','--to',pendingBackup]));
  assert.deepEqual(readFileSync(pendingIndex),pendingBytes);
  assert.deepEqual(readFileSync(join(pendingBackup,'artifacts/index.json')),pendingBytes);
  assert.equal(pendingReceipt.scope,'platform_journal_and_exports');
  const pendingManifest=JSON.parse(readFileSync(join(pendingBackup,'backup.json')));
  assert.equal(pendingReceipt.artifacts,pendingManifest.artifact_files.length);
  assert.equal(pendingReceipt.bytes,pendingManifest.journal_bytes+pendingManifest.artifact_files.reduce((sum,file)=>sum+file.bytes,0));
  const pendingVerified=JSON.parse(cli(pendingBackup,['verify-backup','--sha256',pendingReceipt.sha256]));
  const pendingRestored=JSON.parse(cli(pendingBackup,['restore-state','--sha256',pendingReceipt.sha256,'--to',pendingRestore]));
  assertStoppedReceipts(pendingReceipt,pendingVerified,pendingRestored);
  assert.equal(pendingVerified.journal_compatible,true);assert.equal(pendingRestored.started,false);
  const restoredIndex=join(pendingRestore,'artifacts/index.json');
  assert.deepEqual(readFileSync(restoredIndex),pendingBytes);
  assert.deepEqual(JSON.parse(run(helper,['check',pendingRestore])),{uncertain:1,exports:1});
  assert.equal(JSON.parse(readFileSync(restoredIndex)).records[0].state,'ready');
  assert.deepEqual(readFileSync(pendingIndex),pendingBytes);
  const incompleteState=join(scratch,'incomplete-state'),incompleteBackup=join(scratch,'incomplete-bundle'),incompleteRestore=join(scratch,'incomplete-restored');
  run(helper,['seed',incompleteState]);
  const incompleteIndex=join(incompleteState,'artifacts/index.json');
  const incomplete=JSON.parse(readFileSync(incompleteIndex));
  assert.equal(incomplete.records.length,1);incomplete.records[0].state='pending';
  const incompleteBytes=Buffer.from(JSON.stringify(incomplete)),incompleteBlob=`artifacts/${incomplete.records[0].id}.blob`;
  const prefix=readFileSync(join(incompleteState,incompleteBlob)).subarray(0,1);
  writeFileSync(incompleteIndex,incompleteBytes);writeFileSync(join(incompleteState,incompleteBlob),prefix);
  const incompleteReceipt=JSON.parse(cli(incompleteState,['backup-state','--to',incompleteBackup]));
  const incompleteManifest=JSON.parse(readFileSync(join(incompleteBackup,'backup.json')));
  assert.deepEqual(incompleteManifest.artifact_files,[{path:incomplete.records[0].id+'.blob',bytes:prefix.length,sha256:hash(prefix)}]);
  assert(incomplete.records[0].bytes>prefix.length);
  assert.equal(incompleteReceipt.artifacts,1);
  assert.equal(incompleteReceipt.bytes,lstatSync(join(incompleteBackup,'state.sqlite')).size+prefix.length);
  const incompleteVerified=JSON.parse(cli(incompleteBackup,['verify-backup','--sha256',incompleteReceipt.sha256]));
  const incompleteRestored=JSON.parse(cli(incompleteBackup,['restore-state','--sha256',incompleteReceipt.sha256,'--to',incompleteRestore]));
  assertStoppedReceipts(incompleteReceipt,incompleteVerified,incompleteRestored);
  assert.equal(incompleteVerified.journal_compatible,true);assert.equal(incompleteRestored.started,false);
  for(const copy of [incompleteState,incompleteBackup,incompleteRestore]){
    assert.deepEqual(readFileSync(join(copy,'artifacts/index.json')),incompleteBytes);
    assert.deepEqual(readFileSync(join(copy,incompleteBlob)),prefix);
  }
  assert.deepEqual(JSON.parse(run(helper,['check-incomplete',incompleteRestore])),{uncertain:1,exports:0,failed_exports:1});
  assert.deepEqual(readFileSync(join(incompleteRestore,incompleteBlob)),prefix);
  for(const copy of [incompleteState,incompleteBackup])assert.deepEqual(readFileSync(join(copy,'artifacts/index.json')),incompleteBytes);
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
  // Exercise an independently copied sealed backup; never corrupt the
  // original or let refused restore touch its designated destination.
  const changed=join(scratch,'changed-bundle'),refused=join(scratch,'refused-restore');
  cpSync(bundle,changed,{recursive:true,errorOnExist:true,force:false});
  const changedBlob=join(changed,'artifacts',blob),damaged=Buffer.from(readFileSync(changedBlob));
  assert(damaged.length>0);damaged[0]^=1;writeFileSync(changedBlob,damaged);
  cli(changed,['verify-backup','--sha256',receipt.sha256],{expected:1});
  cli(changed,['restore-state','--sha256',receipt.sha256,'--to',refused],{expected:1});
  assert(!existsSync(refused),'Restore published a destination for a changed sealed backup');
  assert.deepEqual(readFileSync(changedBlob),damaged);
  // Isolate the configuration seal check in another copy, retaining both
  // refusal inputs intact for inspection.
  const configurationCopy=join(scratch,'changed-configuration-bundle');
  cpSync(bundle,configurationCopy,{recursive:true,errorOnExist:true,force:false});
  const changedConfig=join(configurationCopy,'configuration/runtime-enrollment.json');
  const alteredConfig=Buffer.from(readFileSync(changedConfig));
  assert(alteredConfig.length>0);alteredConfig[0]^=1;writeFileSync(changedConfig,alteredConfig);
  cli(configurationCopy,['verify-backup','--sha256',receipt.sha256],{expected:1});
  cli(configurationCopy,['restore-state','--sha256',receipt.sha256,'--to',refused],{expected:1});
  assert(!existsSync(refused),'Restore published a destination for changed sealed configuration');
  assert.deepEqual(readFileSync(changedConfig),alteredConfig);
  assert.deepEqual(readFileSync(join(bundle,'configuration/runtime-enrollment.json')),opaque);
  assert.equal(hash(readFileSync(join(bundle,'backup.json'))),receipt.sha256);
  assert.equal(JSON.parse(cli(bundle,['verify-backup','--sha256',receipt.sha256])).ok,true);
  // The unchanged original must still be publishable to the exact path
  // refused above; verify that failed requests neither reserved it nor
  // dropped the independent custody and export records from the backup.
  const recovery=JSON.parse(cli(bundle,['restore-state','--sha256',receipt.sha256,'--to',refused]));
  assert.equal(recovery.started,false);assert.equal(recovery.installed,false);assert.equal(recovery.activation,false);
  assert.deepEqual(JSON.parse(run(helper,['check',refused])),{uncertain:1,exports:1});
  const final={scope:'isolated_packaged_cli_configuration_backup',manifest_sha256:args[4],source_revision:review.manifest.source_revision,configuration_plan_executed:true,uninstall_proposal_matches:true,backup_sha256:receipt.sha256,journal_only_receipt_verified:true,journal_only_overwrite_refused:true,journal_only_sidecar_collisions_refused:3,pending_index_preserved_until_private_reopen:true,incomplete_pending_preserved_offline:true,incomplete_private_reopen_failed_without_erasure:true,network:'denied',failed_journal_retained:true,failed_export_retained:true,tampered_backup_refused_without_publication:true,tampered_configuration_refused_without_publication:true,original_restores_after_refusals:true,model_posts:0,installed:false,activation:false,uncertainty:1,exports:1,scratch};
  writeFileSync(join(scratch,'receipt.json'),JSON.stringify(final,null,2)+'\n',{mode:0o600});
  console.log(JSON.stringify(final));
} catch(error) {
  console.error('Retained private configuration backup fixture: '+scratch);throw error;
}
