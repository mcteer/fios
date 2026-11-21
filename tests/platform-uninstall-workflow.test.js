import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,chmodSync,writeFileSync,readFileSync,existsSync,rmSync,realpathSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {platformUninstallPlan,platformStatePlan} from '../scripts/lib/platform-state-plan.mjs';

test('uninstall review orders status, stopped backup and retained-data steps',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-uninstall-workflow-'));
  try{
    chmodSync(directory,0o700);
    const state=join(directory,'state');mkdirSync(state,{mode:0o700});
    writeFileSync(join(state,'example.txt'),'retained application data');
    // Workflow metadata only; this unit test neither builds nor runs a release.
    const verified={manifestSHA256:'b'.repeat(64),manifest:{native_inventory:{hosts:['fios-edge-a.lab']},artifacts:[{path:'bin/studioctl',sha256:'a'.repeat(64)}]}};
    const plan=platformUninstallPlan({release:join(directory,'release'),verified,host:'fios-edge-a.lab',source:state,destination:join(directory,'backup with spaces')});
    assert.equal(plan.operation,'platform_uninstall_review');assert.equal(plan.state,'blocked');
    assert.deepEqual(plan.steps.map(step=>step.order),[1,2,3,4,5]);
    assert.equal(plan.steps[1].action,'operator_stop_platform_supervisor_and_manager');
    assert.deepEqual(plan.proposed_commands.map(command=>command.arguments[2]),['status','backup-state']);
    assert.equal(plan.proposed_commands[0].arguments[1],realpathSync.native(state));
    assert.equal(plan.data_removal,false);assert.equal(plan.uninstall_executed,false);
    assert.equal(existsSync(join(directory,'backup with spaces')),false);
    assert.equal(readFileSync(join(state,'example.txt'),'utf8'),'retained application data');
  }finally{rmSync(directory,{recursive:true,force:true});}
});

test('configuration-preserving uninstall proposes the actual bounded backup command without reading or changing configuration',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-uninstall-configuration-'));
  try{
    chmodSync(directory,0o700);
    const state=join(directory,'state'),configuration=join(directory,'configuration with spaces'),destination=join(directory,'backup');
    for(const path of [state,configuration])mkdirSync(path,{mode:0o700});
    const file=join(configuration,'runtime-enrollment.json');writeFileSync(file,'opaque retained bytes',{mode:0o600});
    const verified={manifestSHA256:'b'.repeat(64),manifest:{native_inventory:{hosts:['fios-edge-a.lab']},artifacts:[{path:'bin/studioctl',sha256:'a'.repeat(64)}]}};
    const input={release:join(directory,'release'),verified,host:'fios-edge-a.lab',source:state,configuration,destination};
    const plan=platformUninstallPlan(input);
    assert.deepEqual(plan.proposed_commands[1].arguments,['--state',realpathSync.native(state),'backup-state','--configuration',realpathSync.native(configuration),'--to',join(realpathSync.native(directory),'backup')]);
    assert.equal(plan.proposed_commands[1].artifact_sha256,'a'.repeat(64));
    assert(plan.unverified_at_review.includes('configuration_snapshot_identity_and_bytes'));
    assert.equal(plan.configuration_scope,'six_fixed_opaque_enrollment_documents_not_credentials_or_installed_release');
    assert.equal(plan.state,'blocked');assert.deepEqual(plan.privileged_commands,[]);
    assert.equal(existsSync(destination),false);assert.equal(readFileSync(file,'utf8'),'opaque retained bytes');
    assert.throws(()=>platformStatePlan({...input,operation:'restore',backupSHA256:'c'.repeat(64)}));
    assert.throws(()=>platformUninstallPlan({...input,configuration:join(directory,'missing')}));
    chmodSync(configuration,0o777);assert.throws(()=>platformUninstallPlan(input));
  }finally{rmSync(directory,{recursive:true,force:true});}
});
