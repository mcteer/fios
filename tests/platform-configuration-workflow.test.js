import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,chmodSync,copyFileSync,readFileSync,existsSync,rmSync,renameSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {platformConfigurationPlan,stagePlatformConfiguration,verifyPlatformConfiguration,proposePlatformConfigurationInstall,proposePlatformConfigurationRemoval,proposePlatformRegistration} from '../scripts/lib/platform-state-plan.mjs';

test('configuration workflow renders, stages and verifies templates after state relocation',()=>{
  const directory=mkdtempSync(join(tmpdir(),'fios-configuration-workflow-'));
  try{
    chmodSync(directory,0o700);
    const state=join(directory,'state & exports');mkdirSync(state,{mode:0o700});
    const release=join(directory,'release');mkdirSync(join(release,'launchd'),{recursive:true,mode:0o700});
    const names=['lab.fios.studio.supervisor.plist','lab.fios.studio.session.plist'];
    const artifacts=names.map(name=>{
      const source=new URL(`../platform/studio/deployment/${name}`,import.meta.url);
      copyFileSync(source,join(release,'launchd',name));
      return {path:`launchd/${name}`,sha256:createHash('sha256').update(readFileSync(source)).digest('hex')};
    });
    // Workflow metadata plus genuine repository templates; no executable fixture.
    const verified={manifestSHA256:'b'.repeat(64),manifest:{native_inventory:{hosts:['fios-edge-a.lab','fios-edge-b.lab']},artifacts}};
    const plan=platformConfigurationPlan({release,verified,host:'fios-edge-b.lab',state});
    assert.equal(plan.operation,'platform_configuration_review');assert.equal(plan.host,'fios-edge-b.lab');
    assert.equal(plan.state,'blocked');assert.equal(plan.activation,false);assert.equal(plan.changes_made,false);
    assert.deepEqual(plan.privileged_commands,[]);
    assert.deepEqual(plan.configuration_files.map(file=>file.destination),[
      '/Library/LaunchDaemons/lab.fios.studio.supervisor.plist','/Library/LaunchAgents/lab.fios.studio.session.plist']);
    for(const file of plan.configuration_files){
      assert.ok(file.content.includes(state.replace('&','&amp;')));
      assert.equal(file.content_sha256,createHash('sha256').update(file.content).digest('hex'));
      assert.equal(file.owner,'root:wheel');assert.equal(file.mode,0o644);
      assert.equal(existsSync(join(directory,'rendered')),false);
    }
    assert.ok(plan.rollback_steps.includes('retain_current_state_exports_and_configuration'));
    const staged=stagePlatformConfiguration({release,verified,host:'fios-edge-b.lab',state,destination:join(directory,'rendered')});
    renameSync(state,join(directory,'retained-state'));
    const saved=verifyPlatformConfiguration({release,verified,host:'fios-edge-b.lab',bundle:staged.destination,reviewSHA256:staged.review_sha256});
    assert.equal(saved.scope,'declared_configuration_files');assert.equal(saved.files,2);
    assert.equal(saved.state,'review_required');assert.equal(saved.installed,false);assert.equal(saved.activation,false);
    const proposal=proposePlatformConfigurationInstall({release,verified,host:'fios-edge-b.lab',bundle:staged.destination,reviewSHA256:staged.review_sha256});
    assert.equal(proposal.state,'blocked');assert.equal(proposal.commands_authorized,false);
    assert.equal(proposal.requires_operator_execution,true);assert.equal(proposal.native_authority,false);
    assert.deepEqual(proposal.privileged_commands,[]);assert.equal(proposal.proposed_file_commands.length,2);
    assert.deepEqual(proposal.proposed_file_commands.map(file=>file.destination),plan.configuration_files.map(file=>file.destination));
    for(const file of proposal.proposed_file_commands){
      assert.equal(file.program,'/usr/bin/install');
      assert.deepEqual(file.argv,['-o','root','-g','wheel','-m','0644',file.source,file.destination]);
      assert.equal(createHash('sha256').update(readFileSync(file.source)).digest('hex'),file.sha256);
    }
    assert.throws(()=>proposePlatformConfigurationInstall({release,verified,host:'fios-edge-a.lab',bundle:staged.destination,reviewSHA256:staged.review_sha256}));
    const removal=proposePlatformConfigurationRemoval({release,verified,host:'fios-edge-b.lab',bundle:staged.destination,reviewSHA256:staged.review_sha256});
    assert.equal(removal.state,'blocked');assert.equal(removal.commands_authorized,false);
    assert.equal(removal.configuration_removed,false);assert.equal(removal.credentials_retained,true);
    assert.equal(removal.state_and_exports_retained,true);assert.equal(removal.native_authority,false);
    assert.equal(removal.proposed_file_commands,undefined);assert.deepEqual(removal.privileged_commands,[]);
    assert.equal(removal.proposed_file_removals.length,2);
    assert.deepEqual(removal.proposed_file_removals.map(file=>file.argv),plan.configuration_files.map(file=>[file.destination]));
    assert(removal.mandatory_preconditions.includes('reviewed_registration_removed_or_persistently_disabled'));
    const registrationOptions={release,verified,host:'fios-edge-b.lab',bundle:staged.destination,reviewSHA256:staged.review_sha256,uid:'501'};
    const activation=proposePlatformRegistration({...registrationOptions,operation:'activate'});
    assert.equal(activation.state,'blocked');assert.equal(activation.commands_authorized,false);
    assert.equal(activation.registration_changed,false);assert.equal(activation.desired_service_state_changed,false);
    assert.equal(activation.native_inference_uncertainty_retained,true);assert.deepEqual(activation.privileged_commands,[]);
    const expected=[['enable','system/lab.fios.studio.supervisor'],['enable','gui/501/lab.fios.studio.session'],
      ['bootstrap','system','/Library/LaunchDaemons/lab.fios.studio.supervisor.plist'],
      ['bootstrap','gui/501','/Library/LaunchAgents/lab.fios.studio.session.plist']];
    assert.deepEqual(activation.proposed_registration_commands.map(command=>command.argv),expected);
    const unregister=proposePlatformRegistration({...registrationOptions,operation:'remove'});
    assert.deepEqual(unregister.proposed_registration_commands.map(command=>command.argv),[
      ['disable','system/lab.fios.studio.supervisor'],['disable','gui/501/lab.fios.studio.session'],
      ['bootout','system/lab.fios.studio.supervisor'],['bootout','gui/501/lab.fios.studio.session']]);
    assert(unregister.after_commands.includes('create_and_verify_stopped_state_configuration_backup_before_file_removal'));
    for(const uid of ['0','01','4294967296','501/name','501\n','501\r',501,true])assert.throws(()=>proposePlatformRegistration({...registrationOptions,uid,operation:'activate'}));
    const reordered=JSON.parse(readFileSync(join(staged.destination,'review.json')));
    reordered.files.reverse();reordered.configuration_files.reverse();
    const reorderedBytes=JSON.stringify(reordered,null,2)+'\n';writeFileSync(join(staged.destination,'review.json'),reorderedBytes);
    const reorderedSHA=createHash('sha256').update(reorderedBytes).digest('hex');
    const reorderedActivation=proposePlatformRegistration({...registrationOptions,reviewSHA256:reorderedSHA,operation:'activate'});
    assert.deepEqual(reorderedActivation.proposed_registration_commands.map(command=>command.argv),expected);
    assert.equal(saved.changes_made,false);assert.equal(existsSync(state),false);
    assert.equal(existsSync(join(directory,'retained-state')),true);

  }finally{rmSync(directory,{recursive:true,force:true});}
});
