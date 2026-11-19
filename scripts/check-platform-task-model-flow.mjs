#!/usr/bin/env node
// Normal CLI completion, owner cancellation and service-unavailable reporting; local MOCK only.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readdirSync,copyFileSync,chmodSync,readFileSync,writeFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {DatabaseSync} from 'node:sqlite';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-manager-cli-');
const source=join(directory,'Main.swift'),binary=join(directory,'manager'),standin=join(directory,'runtime-unused');
const python=join(root,'.venv/bin/python');
const sha=data=>createHash('sha256').update(data).digest('hex');
const environment={PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty',DOCKER_CONFIG:'/var/empty'};
function command(program,args,timeout=180000){const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});assert.equal(result.status,0,'Normal model flow command failed: '+(result.stderr??''));return result.stdout;}
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=8000){const deadline=performance.now()+timeout;while(performance.now()<deadline){const result=await check();if(result)return result;await delay(20);}throw Error('Normal CLI model workflow deadline');}
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ManagerExecutionLive.swift.fixture'),source);
copyFileSync('/usr/bin/false',standin);chmodSync(standin,0o700);
const core=join(root,'platform/studio/Sources/StudioCore');
command('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n)),source,'-o',binary]);
command('swift',['build','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl','-j','2']);
const cli=join(command('swift',['build','--package-path','platform/studio','--show-bin-path']).trim(),'studioctl');
async function modelCase(scenario){
const caseDirectory=join(directory,scenario);mkdirSync(caseDirectory,{mode:0o700});
const state=join(caseDirectory,'state'),nativeState=join(caseDirectory,'native'),children=[];
const token=randomBytes(32).toString('base64');let mock,manager,posts=0,port,streamFailure;
function task(operation,payload,expectedError){
 const id=randomUUID(),result=spawnSync(cli,['--state',state,'task'],{cwd:root,encoding:'utf8',timeout:3000,input:JSON.stringify({version:1,id,operation,payload:{...payload,owner:token}})});
 assert.equal(result.status,expectedError?1:0,'Unexpected CLI task exit');const reply=JSON.parse(result.stdout);assert.equal(reply.id,id);
 if(expectedError){assert.equal(reply.ok,false);assert.equal(reply.error,expectedError);return;}
 assert.equal(reply.ok,true);assert(reply.result);return reply.result;
}
async function replaceManager(previousEpoch){
 manager.kill('SIGTERM');await until(()=>exited(manager),5000);
 manager=spawn(binary,[state,standin,sha(readFileSync(standin)),'/fixture/unused.sock','sha256:'+'a'.repeat(64),'disabled'],{cwd:root,env:environment,stdio:'ignore'});children.push(manager);
 await until(()=>{assert(!exited(manager),'Replacement private manager exited');return existsSync(join(state,'observe.sock'));});
 const replacement=JSON.parse(command(cli,['--state',state,'status'],3000));assert.notEqual(replacement.epoch,previousEpoch);
}
try {
 mkdirSync(state,{mode:0o700});mkdirSync(nativeState,{mode:0o700});
 manager=spawn(binary,[state,standin,sha(readFileSync(standin)),'/fixture/unused.sock','sha256:'+'a'.repeat(64),'models',python],{cwd:root,env:environment,stdio:['pipe','ignore','ignore']});children.push(manager);
 await until(()=>{assert(!exited(manager),'Private manager exited');return existsSync(join(state,'observe.sock'));});
 const status=JSON.parse(command(cli,['--state',state,'status'],3000));
 mock=spawn(python,['-I','-B',join(root,'tests/fixtures/platform/native-server.py'),nativeState,status.epoch],{cwd:root,env:environment,stdio:['pipe','pipe','pipe']});children.push(mock);
 let buffered='';
 mock.stdout.on('data',bytes=>{try{buffered+=bytes;assert(buffered.length<4096);while(buffered.includes('\n')){const end=buffered.indexOf('\n'),value=JSON.parse(buffered.slice(0,end));buffered=buffered.slice(end+1);if(value.port!==undefined)port=value.port;else{assert.equal(value.posts,posts+1);posts=value.posts;}}}catch(error){streamFailure=error;}});
 mock.stderr.on('data',()=>{streamFailure=Error('Local model mock failed');});
 await until(()=>{if(streamFailure)throw streamFailure;assert(!exited(mock));return port;});
 manager.stdin.end(JSON.stringify({base:`http://127.0.0.1:${port}/v1`,path:join(nativeState,'observe.sock'),epoch:status.epoch}));
 await until(()=>existsSync(join(caseDirectory,'model-cache-ready')));
 let content=['complete','upload_restart'].includes(scenario)?'ordinary CLI text 👋\n'.repeat(2200):scenario==='cancel'?'ordinary delayed reply':'ordinary unavailable reply';
 if(scenario==='unicode'){
  const prefix=Buffer.from(JSON.stringify([{role:'user',content:'MARKER'}])).indexOf('MARKER');
  content='x'.repeat(32768-prefix-2)+'👋漢字e\u0301\n';
  writeFileSync(join(nativeState,'expected-user-text.sha256'),sha(Buffer.from(content)),{mode:0o600});
 }
 const messages=[{role:'user',content}];
 if(scenario==='invalid_history')messages.unshift({role:'assistant',content:''});
 const data=Buffer.from(JSON.stringify(messages));
 if(scenario==='unicode'){assert.equal(data[32766],0xf0);assert.equal(data[32768],0x91);}
 const manifest={phase:'begin',idempotency:randomUUID(),kind:'model',length:data.length,sha256:sha(data),lifetime:60000,model:'fixture/model',image:null,memory:0,cpus:0};
 const created=task('job.create',manifest);
 assert.equal(created.state,'reserved');const job=created.job,deadline=created.lease.deadline_at;
 const observed=task('job.status',{job});assert.equal(observed.lease.expires_at,created.lease.expires_at);
 if(scenario==='complete'){
  task('job.create',{...manifest,sha256:sha(Buffer.from('different upload'))},'job_conflict');
  const retained=task('job.status',{job});
  assert.equal(retained.state,'reserved');assert.equal(retained.lease.expires_at,created.lease.expires_at);
  assert.equal(posts,0);
 }
 await delay(25);const renewed=task('job.renew',{job});assert(renewed.lease.expires_at>created.lease.expires_at);assert.equal(renewed.lease.deadline_at,deadline);
 let chunks=0;for(let offset=0;offset<data.length;offset+=32768){task('job.create',{phase:'chunk',job,index:chunks++,data:data.subarray(offset,offset+32768).toString('base64')});if(scenario==='upload_restart')break;}
 if(scenario==='upload_restart'){
  assert.equal(posts,0);await replaceManager(status.epoch);
  let restored;
  await until(()=>{restored=task('job.status',{job});return restored.state==='removed';});
  assert.equal(restored.lease.revoked,true);assert.equal(restored.unresolved_managed_requests,0);assert.equal(restored.event,undefined);
  const replay=task('job.create',manifest);assert.equal(replay.job,job);assert.equal(replay.state,'removed');assert.equal(replay.lease.revoked,true);
  const acknowledgement=task('job.create',{phase:'end',job});assert.equal(acknowledgement.state,'removed');assert.equal(acknowledgement.lease.deadline_at,deadline);
  await delay(50);assert.equal(posts,0);assert.equal(JSON.parse(command(cli,['--state',state,'status'],3000)).worker_reservations,0);
  return {scenario,restart_checked:true,input_bytes:data.length,input_chunks:chunks,partial_upload:true,replay_status_only:true,state:restored.state,mock_model_posts:posts,worker_slots_after_completion:0};
 }
 if(['invalid_history','replaced_source','duplicate_chunk'].includes(scenario)){
  if(scenario==='replaced_source')writeFileSync(join(nativeState,'replace-source-epoch'),'mock',{flag:'wx',mode:0o600});
  if(scenario==='duplicate_chunk'){
   task('job.create',{phase:'chunk',job,index:0,data:data.toString('base64')},'invalid_request');
   assert.equal(task('job.create',{phase:'end',job}).lease.revoked,true);
  }else task('job.create',{phase:'end',job},'invalid_request');
  const final=await until(()=>{const s=task('job.status',{job});return s.state==='removed' ? s:null;});
  assert.equal(final.unresolved_managed_requests,0);
  assert.equal(JSON.parse(command(cli,['--state',state,'status'],3000)).worker_reservations,0);
  assert.equal(posts,0);
  manager.kill('SIGTERM');await until(()=>exited(manager));assert.equal(manager.exitCode,0);
  const db=new DatabaseSync(join(state,'state.sqlite'),{readOnly:true});
  try {assert.equal(db.prepare('SELECT count(*) AS count FROM inference WHERE job=?').get(job).count,0);}
  finally {db.close();}
  return {scenario,state:final.state,mock_model_posts:posts,worker_attempts:0,worker_slots_after_completion:0};
 }
 task('job.create',{phase:'end',job});
 if(scenario==='complete'){
  task('job.create',{phase:'chunk',job,index:0,data:Buffer.from('not the original input').toString('base64')},'invalid_request');
  const duplicate=task('job.create',{phase:'end',job});
  const replay=task('job.create',manifest);
  // The fast mock may already have completed; both replies must describe
  // the original job, not create another attempt or extend its lease.
  for(const result of [duplicate,replay]){
   assert.equal(result.job,job);assert.equal(result.lease.deadline_at,deadline);
   assert.equal(result.lease.expires_at,renewed.lease.expires_at);
  }
 }
 let wasRunning=false;
 if(scenario==='cancel'){
  await until(()=>{if(streamFailure)throw streamFailure;return posts===1;});
  const active=task('job.status',{job});assert.equal(active.state,'running');wasRunning=true;
  const cancelled=task('job.cancel',{job});assert.equal(cancelled.lease.revoked,true);
 }
 let text='',terminal,failureCode,final,ordinal=0;
 await until(()=>{
  if(streamFailure)throw streamFailure;assert(!exited(manager)&&!exited(mock));
  const response=task('job.status',{job});
  if(response.event){assert.equal(response.event.event_index,ordinal++);if(response.event.type==='model.text')text+=response.event.content;else if(response.event.type==='model.done'){terminal=response.event.status;failureCode=response.event.code;}}
  if(response.state==='removed'&&(scenario==='cancel'||terminal)){final=response;return true;}return false;
 },15000);
 if(['complete','unicode'].includes(scenario)){assert.equal(text,'MOCK_ONLY');assert.equal(terminal,'complete');}
 if(scenario==='unavailable'){assert.equal(text,'');assert.equal(terminal,'failed');assert.equal(failureCode,'upstream_http');}
 assert.equal(posts,1);assert.equal(final.lease.deadline_at,deadline);assert.equal(final.lease.revoked,true);
 await until(()=>JSON.parse(command(cli,['--state',state,'status'],3000)).worker_reservations===0);
 assert.equal(final.unresolved_managed_requests,1);
 let restartChecked=false;
 if(scenario==='complete'){
  await replaceManager(status.epoch);
  const restored=task('job.status',{job});assert.equal(restored.state,'removed');assert.equal(restored.lease.revoked,true);assert.equal(restored.event,undefined);assert.equal(restored.unresolved_managed_requests,1);
  const acknowledgement=task('job.create',{phase:'end',job});assert.equal(acknowledgement.state,'removed');assert.equal(acknowledgement.lease.deadline_at,deadline);
  await delay(50);assert.equal(posts,1);assert.equal(JSON.parse(command(cli,['--state',state,'status'],3000)).worker_reservations,0);restartChecked=true;
 }
 return {scenario,unicode_boundary_preserved:scenario==='unicode',restart_checked:restartChecked,input_bytes:data.length,input_chunks:chunks,output_events:ordinal,terminal:terminal??null,failure_code:failureCode??null,state:final.state,cancelled_while_running:wasRunning,lease_read_did_not_extend:true,renewal_extended_expiry:true,deadline_unchanged:true,mock_model_posts:posts,worker_slots_after_completion:0};
} finally {
 if(manager&&!exited(manager))manager.kill('SIGTERM');if(mock&&!exited(mock))mock.stdin.end();
 await until(()=>children.every(exited),5000);
}
}
const records=[];
for(const scenario of ['complete','cancel','unavailable','upload_restart','unicode','invalid_history','replaced_source','duplicate_chunk'])records.push(await modelCase(scenario));
const receipt={scope:'normal_cli_model_job_completion_cancellation_and_service_failure',records,real_model_requests:0,runtime_actions:0,native_acceptance:false,cli_sha256:sha(readFileSync(cli)),manager_sha256:sha(readFileSync(binary))};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({ok:true,directory,...receipt}));
