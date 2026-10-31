import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,chmodSync,copyFileSync,readFileSync,existsSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {platformConfigurationPlan} from '../scripts/lib/platform-state-plan.mjs';

test('configuration review renders both packaged launchd templates for the selected state',()=>{
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
  }finally{rmSync(directory,{recursive:true,force:true});}
});
