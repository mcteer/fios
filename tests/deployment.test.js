import test from 'node:test';
import assert from 'node:assert/strict';
import {deployRelease,greenChecks,REQUIRED_CHECKS} from '../scripts/deploy.mjs';

const checks=()=>REQUIRED_CHECKS.map(name=>({name,status:'completed',conclusion:'success'}));
test('delivery gate requires all exact checks completed successfully, never missing/skipped/pending',()=>{
  assert.equal(greenChecks(checks()),true);
  assert.equal(greenChecks([]),false);
  assert.equal(greenChecks(checks().slice(1)),false);
  for(const status of ['queued','in_progress']){const c=checks();c[0].status=status;assert.equal(greenChecks(c),false);}
  for(const conclusion of ['failure','cancelled','skipped',null]){const c=checks();c[0].conclusion=conclusion;assert.equal(greenChecks(c),false);}
});

function fixture(failure){
  const calls=[];
  const image='fios:'+'a'.repeat(40);
  const compose=async(selected,args)=>{
    calls.push({kind:'compose',selected,args});
    if(args[0]==='ps')return 'a'.repeat(64);
    if(failure==='stop'&&selected===image&&args[0]==='stop')throw new Error('sensitive details');
    if(failure==='verify'&&selected===image&&args[0]==='exec')throw new Error('sensitive details');
    if(failure==='rollback'&&args[0]==='exec')throw new Error('sensitive details');
    return 'verified';
  };
  const run=async args=>{
    calls.push({kind:'docker',args});
    if(args[0]==='inspect')return args.includes('{{.Image}}')?'sha256:'+'b'.repeat(64):'disposable_data';
    if(failure==='backup'&&args[0]==='run')throw new Error('sensitive details');
    return '';
  };
  return {calls,image,compose,run,stamp:'abc-123'};
}
test('stopped backup precedes replacement; exact image and old-image/backup references are retained',async()=>{
  const f=fixture();const result=await deployRelease(f);
  const backup=f.calls.findIndex(c=>c.kind==='docker'&&c.args[0]==='run');
  const stop=f.calls.findIndex(c=>c.args[0]==='stop');
  const up=f.calls.findIndex(c=>c.args[0]==='up');
  assert.ok(stop<backup&&backup<up);
  assert.equal(f.calls[up].selected,f.image);
  assert.ok(f.calls[backup].args.includes('--network'));
  assert.equal(result.previousImage,'fios:rollback-abc-123');
  assert.equal(result.backup,'disposable_data/backups/before-abc-123');
});
test('backup, stop and verification failures restore previous image; failed rollback is explicit',async()=>{
  for(const failure of ['backup','stop','verify','rollback']){
    const f=fixture(failure);
    await assert.rejects(()=>deployRelease(f),new RegExp(failure==='rollback'?'deployment_and_rollback_failed':'deployment_failed_previous_image_restored'));
    assert.ok(f.calls.some(c=>c.selected==='fios:rollback-abc-123'&&c.args[0]==='up'));
    if(failure==='backup')assert.ok(!f.calls.some(c=>c.selected===f.image&&c.args[0]==='up'));
  }
});
test('superseded revision never stops production or creates a backup',async()=>{
  const f=fixture();
  await assert.rejects(()=>deployRelease({...f,beforeStop:async()=>{throw new Error('superseded');}}),/superseded/);
  assert.ok(!f.calls.some(c=>c.args[0]==='stop'||c.args[0]==='run'));
});
