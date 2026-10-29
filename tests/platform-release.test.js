import test from 'node:test';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,rmSync,chmodSync,symlinkSync,unlinkSync,linkSync,existsSync,realpathSync,cpSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {validatePlatformManifest,decodePlatformManifest,validatePlatformRelease,platformArtifactModes} from '../scripts/lib/platform-release.mjs';
const template=JSON.parse(readFileSync(new URL('../platform/studio/deployment/release.json',import.meta.url)));
test('native development manifest pins toolchain/locks and cannot authorize activation',()=>{
  const value=validatePlatformManifest(template,{template:true});
  assert.equal(value.architecture,'arm64');
  const legacy={...template,journal_schema:7};
  assert.throws(()=>validatePlatformManifest(legacy,{template:true}));
  assert.equal(validatePlatformManifest(legacy,{template:true,journalSchema:7}).journal_schema,7);
  assert.throws(()=>validatePlatformManifest(legacy,{template:true,journalSchema:9}));
  assert.equal(value.native_inventory.all_client_coverage,'unsupported');
  assert.equal(value.native_inventory.orbctl_cli_sha256,'b2793e99e3f452b86233d59cd5e503e069821224c022628f52521dc5b4bcab8a');
  const missingNativeCLI=structuredClone(template);delete missingNativeCLI.native_inventory.orbctl_cli_sha256;
  assert.throws(()=>validatePlatformManifest(missingNativeCLI,{template:true}));
  for(const flag of Object.values(value.activation))assert.equal(flag,false);
  assert.throws(()=>validatePlatformManifest({...template,activation:{...template.activation,managed_inference:true}},{template:true}));
  assert.throws(()=>validatePlatformManifest({...template,approval:'production'},{template:true}));
  assert.throws(()=>validatePlatformManifest({...template,extra:'ignored'},{template:true}));
  assert.throws(()=>validatePlatformManifest({...template,journal_schema:9},{template:true}));
});
test('release receipt decoder rejects duplicate/noncanonical JSON and unreviewed fields',()=>{
  const canonical=JSON.stringify(template,null,2)+'\n';
  assert.equal(decodePlatformManifest(Buffer.from(canonical),{template:true}).schema,1);
  assert.throws(()=>decodePlatformManifest(Buffer.from(canonical.replace('"schema": 1','"schema": 1, "schema": 1')),{template:true}));
  assert.throws(()=>decodePlatformManifest(Buffer.from(JSON.stringify(template)),{template:true}));
  assert.throws(()=>validatePlatformManifest({...template,approved_sandbox_images:['sha256:'+'a'.repeat(64)]},{template:true}));
});
test('reviewed release tree refuses changed bytes, extra files, symlinks and hardlinks',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-release-test-')),outside=mkdtempSync(join(tmpdir(),'fios-release-link-'));
  try{
    chmodSync(directory,0o700);
    const artifacts=[];
    for(const [path,mode] of Object.entries(platformArtifactModes)){
      mkdirSync(dirname(join(directory,path)),{recursive:true,mode:0o700});
      const bytes=Buffer.alloc(32);
      if(path.startsWith('bin/')){bytes.writeUInt32LE(0xfeedfacf,0);bytes.writeUInt32LE(0x0100000c,4);}
      else bytes.write('fixture-only');
      writeFileSync(join(directory,path),bytes,{mode});
      artifacts.push({path,sha256:createHash('sha256').update(bytes).digest('hex'),bytes:bytes.length,mode});
    }
    const receipt={...template,source_revision:'a'.repeat(40),source_tree_sha256:'b'.repeat(64),artifacts,package_complete:false};
    const bytes=Buffer.from(JSON.stringify(receipt,null,2)+'\n');
    writeFileSync(join(directory,'release.json'),bytes,{mode:0o600});
    const hash=createHash('sha256').update(bytes).digest('hex');
    assert.equal(validatePlatformRelease(directory,hash).activation,false);
    const review=spawnSync(process.execPath,['scripts/install-platform.mjs','plan','--release',directory,'--sha256',hash,'--host','fios-edge-a.lab'],{encoding:'utf8',timeout:3000});
    assert.equal(review.status,0);
    const plan=JSON.parse(review.stdout);
    assert.equal(plan.state,'blocked');assert.equal(plan.changes_made,false);assert.deepEqual(plan.privileged_commands,[]);
    assert.ok(plan.blockers.includes('authoritative_native_coverage_unproven'));
    const apply=spawnSync(process.execPath,['scripts/install-platform.mjs','apply','--release',directory,'--sha256',hash,'--host','fios-edge-a.lab'],{encoding:'utf8',timeout:3000});
    assert.equal(apply.status,1);assert.equal(apply.stdout,'');
    const state=join(outside,'state'),destination=join(outside,'backup with spaces');
    mkdirSync(state,{mode:0o700});
    const invoke=extra=>spawnSync(process.execPath,['scripts/install-platform.mjs',...extra],{encoding:'utf8',timeout:3000});
    const common=['--release',directory,'--sha256',hash,'--host','fios-edge-a.lab'];
    const backupReview=invoke(['plan-backup',...common,'--state',state,'--to',destination]);
    assert.equal(backupReview.status,0,backupReview.stderr);
    const backupPlan=JSON.parse(backupReview.stdout),canonicalState=realpathSync.native(state),canonicalDestination=join(realpathSync.native(outside),'backup with spaces');
    assert.equal(backupPlan.changes_made,false);assert.equal(backupPlan.activation,false);
    assert.deepEqual(backupPlan.privileged_commands,[]);
    assert.equal(backupPlan.proposed_commands[0].program,join(directory,'bin/studioctl'));
    assert.deepEqual(backupPlan.proposed_commands[0].arguments,['--state',canonicalState,'backup-state','--to',canonicalDestination]);
    assert.ok(backupPlan.unverified_at_review.includes('source_writer_stopped'));
    assert.equal(existsSync(destination),false); // Stub Mach-O cannot execute: review must never spawn it.
    const backupDigest='c'.repeat(64),restored=join(outside,'restored');
    const restoreReview=invoke(['plan-restore',...common,'--backup',state,'--backup-sha256',backupDigest,'--to',restored]);
    assert.equal(restoreReview.status,0,restoreReview.stderr);
    const restorePlan=JSON.parse(restoreReview.stdout);
    assert.deepEqual(restorePlan.proposed_commands.map(command=>command.arguments[2]),['verify-backup','restore-state']);
    assert.ok(restorePlan.unverified_at_review.includes('backup_origin'));assert.equal(existsSync(restored),false);
    for(const command of [...backupPlan.proposed_commands,...restorePlan.proposed_commands]){
      assert.equal(command.execution,'operator_only');assert.equal(command.artifact_sha256,artifacts.find(item=>item.path==='bin/studioctl').sha256);
    }
    const previous=join(outside,'previous-release');cpSync(directory,previous,{recursive:true});
    function previousReceipt(schema){
      const old={...receipt,journal_schema:schema,source_revision:'c'.repeat(40)};
      const data=Buffer.from(JSON.stringify(old,null,2)+'\n');writeFileSync(join(previous,'release.json'),data,{mode:0o600});
      return createHash('sha256').update(data).digest('hex');
    }
    let previousHash=previousReceipt(8);
    const rollbackArgs=()=>[...common,'--previous',previous,'--previous-sha256',previousHash,'--backup',state,'--backup-sha256','d'.repeat(64),'--to',restored];
    const rollback=invoke(['plan-rollback',...rollbackArgs()]);assert.equal(rollback.status,0,rollback.stderr);
    const rollbackPlan=JSON.parse(rollback.stdout);
    assert.equal(rollbackPlan.operation,'stopped_state_rollback_review');assert.equal(rollbackPlan.previous_journal_schema,8);
    assert.equal(rollbackPlan.current_manifest_sha256,hash);assert.equal(rollbackPlan.previous_manifest_sha256,previousHash);
    assert.equal(rollbackPlan.changes_made,false);assert.equal(rollbackPlan.activation,false);assert.deepEqual(rollbackPlan.privileged_commands,[]);
    assert.equal(rollbackPlan.proposed_commands[0].program,join(previous,'bin/studioctl'));
    assert.equal(rollbackPlan.proposed_commands[1].arguments.at(-1),join(realpathSync.native(outside),'restored'));assert.equal(existsSync(restored),false);
    previousHash=previousReceipt(7);
    assert.equal(invoke(['plan-rollback',...rollbackArgs()]).status,1,'Legacy release silently entered the default current-schema path');
    const seven=invoke(['plan-rollback-seven',...rollbackArgs()]);assert.equal(seven.status,0,seven.stderr);
    assert.equal(JSON.parse(seven.stdout).previous_journal_schema,7);
    const asCurrent=invoke(['plan','--release',previous,'--sha256',previousHash,'--host','fios-edge-a.lab']);assert.equal(asCurrent.status,1);
    previousHash=previousReceipt(8);
    const same=invoke(['plan-rollback',...common,'--previous',directory,'--previous-sha256',hash,'--backup',state,'--backup-sha256','d'.repeat(64),'--to',restored]);assert.equal(same.status,1);
    assert.equal(invoke(['plan-rollback',...rollbackArgs(),'--execute']).status,1);
    const sourceLink=join(outside,'state-link');symlinkSync(state,sourceLink);
    for(const extra of [
      ['plan-backup',...common,'--state',sourceLink,'--to',destination],
      ['plan-backup',...common,'--state',state,'--to',state],
      ['plan-backup',...common,'--state',state,'--to',join(state,'nested')],
      ['plan-restore',...common,'--backup',state,'--backup-sha256','bad','--to',restored],
      ['plan-backup',...common,'--state',state,'--to',destination,'--execute'],
    ]){const refused=invoke(extra);assert.equal(refused.status,1);assert.equal(refused.stdout,'');}
    unlinkSync(sourceLink);
    chmodSync(outside,0o755);
    assert.equal(invoke(['plan-backup',...common,'--state',state,'--to',destination]).status,1);
    chmodSync(outside,0o700);
    assert.throws(()=>validatePlatformRelease(directory,'0'.repeat(64)));
    writeFileSync(join(directory,'unexpected'),Buffer.from('fixture-only'));
    assert.throws(()=>validatePlatformRelease(directory,hash));unlinkSync(join(directory,'unexpected'));
    const target=join(directory,'sandbox/runner.py'),backup=readFileSync(target);
    writeFileSync(target,Buffer.from('changed'));assert.throws(()=>validatePlatformRelease(directory,hash));
    unlinkSync(target);symlinkSync('../Dockerfile',target);assert.throws(()=>validatePlatformRelease(directory,hash));
    unlinkSync(target);writeFileSync(target,backup,{mode:0o644});
    linkSync(target,join(outside,'link'));assert.throws(()=>validatePlatformRelease(directory,hash));unlinkSync(join(outside,'link'));
    chmodSync(target,0o666);assert.throws(()=>validatePlatformRelease(directory,hash));
    chmodSync(target,0o4644);assert.throws(()=>validatePlatformRelease(directory,hash));
    chmodSync(target,0o644);
    for(const path of [join(directory,'release.json'),target]){
      const saved=readFileSync(path),mode=path===target?0o644:0o600;
      unlinkSync(path);
      assert.equal(spawnSync('/usr/bin/mkfifo',[path],{timeout:1000}).status,0);
      const refused=invoke(['plan',...common]);
      assert.equal(refused.error,undefined,'Release review blocked on a FIFO');
      assert.equal(refused.status,1);assert.equal(refused.stdout,'');
      unlinkSync(path);writeFileSync(path,saved,{mode});
      const race=spawnSync(process.execPath,['--input-type=module','-e',`
        import fs from 'node:fs';
        import {syncBuiltinESMExports} from 'node:module';
        import {spawnSync} from 'node:child_process';
        const [directory,hash,target]=process.argv.slice(1),open=fs.openSync;
        let replaced=false;
        fs.openSync=(path,...args)=>{
          if(path===target&&!replaced){
            replaced=true;fs.unlinkSync(target);
            if(spawnSync('/usr/bin/mkfifo',[target],{timeout:1000}).status!==0)throw Error('fixture');
          }
          return open(path,...args);
        };
        syncBuiltinESMExports();
        const {validatePlatformRelease}=await import(${JSON.stringify(new URL('../scripts/lib/platform-release.mjs',import.meta.url).href)});
        try{validatePlatformRelease(directory,hash);process.exitCode=2;}
        catch{process.exitCode=replaced?1:3;}
      `,directory,hash,path],{encoding:'utf8',timeout:3000});
      assert.equal(race.error,undefined,'Release review blocked on a raced FIFO');
      assert.equal(race.status,1,'Special-file race did not reach and fail the reader');
      assert.equal(race.stdout,'');
      unlinkSync(path);writeFileSync(path,saved,{mode});
    }
  }finally{rmSync(directory,{recursive:true,force:true});rmSync(outside,{recursive:true,force:true});}
});
