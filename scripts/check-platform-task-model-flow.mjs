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
const token=randomBytes(32).toString('base64');let mock,manager,posts=0,port,streamFailure,buffered='',mockClosed=false,caseFailed=false;
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
 mock.once('close',()=>{mockClosed=true;});
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
 const manifest={phase:'begin',idempotency:randomUUID(),kind:'model',length:data.length,sha256:sha(scenario==='digest_mismatch'?Buffer.from('different upload'):data),lifetime:60000,model:'fixture/model',image:null,memory:0,cpus:0};
 const created=task('job.create',manifest);
 assert.equal(created.state,'reserved');const job=created.job,deadline=created.lease.deadline_at;
 if(scenario==='reserved_capacity'){
  const second=task('job.create',{...manifest,idempotency:randomUUID()});
  const thirdManifest={...manifest,idempotency:randomUUID()};
  assert.notEqual(second.job,job);assert.equal(second.state,'reserved');
  task('job.create',thirdManifest,'tracking_limit');
  for(const original of [created,second]){
   const current=task('job.status',{job:original.job});
   assert.equal(current.state,'reserved');assert.equal(current.lease.expires_at,original.lease.expires_at);
  }
  assert.equal(task('job.cancel',{job:second.job}).lease.revoked,true);
  await until(()=>task('job.status',{job:second.job}).state==='removed');
  const third=task('job.create',thirdManifest);assert.equal(third.state,'reserved');assert.notEqual(third.job,second.job);
  for(const id of [job,third.job])assert.equal(task('job.cancel',{job:id}).lease.revoked,true);
  await until(()=>[job,third.job].every(id=>task('job.status',{job:id}).state==='removed'));
  const summary=JSON.parse(command(cli,['--state',state,'status'],3000));
  assert.equal(summary.worker_reservations,0);assert.equal(summary.unresolved_requests,0);assert.equal(posts,0);
  return {scenario,reserved_slots:2,reused_after_local_cancel:true,mock_model_posts:0,worker_slots_after_completion:0};
 }
 const observed=task('job.status',{job});assert.equal(observed.lease.expires_at,created.lease.expires_at);
 if(scenario==='complete'){
  task('job.create',{...manifest,sha256:sha(Buffer.from('different upload'))},'job_conflict');
  const retained=task('job.status',{job});
  assert.equal(retained.state,'reserved');assert.equal(retained.lease.expires_at,created.lease.expires_at);
  assert.equal(posts,0);
 }
 await delay(25);const renewed=task('job.renew',{job});assert(renewed.lease.expires_at>created.lease.expires_at);assert.equal(renewed.lease.deadline_at,deadline);
 let chunks=0;for(let offset=0;offset<data.length;offset+=32768){task('job.create',{phase:'chunk',job,index:chunks++,data:data.subarray(offset,offset+32768).toString('base64')});if(scenario==='upload_restart')break;}
 if(scenario==='upload_timeout'){
  // Complete byte input, but never send end before the original 10s upload
  // deadline. The run loop must revoke it independently of the job lease.
  const timedOut=await until(()=>{
   const current=task('job.status',{job});
   assert.notEqual(current.state,'running');
   return current.state==='removed'?current:false;
  },16000);
  assert.equal(timedOut.lease.revoked,true);assert.equal(timedOut.lease.expires_at,renewed.lease.expires_at);
  task('job.create',{phase:'chunk',job,index:0,data:data.subarray(0,32768).toString('base64')},'invalid_request');
  const late=task('job.create',{phase:'end',job});assert.equal(late.state,'removed');assert.equal(late.job,job);
  // Reuse both ordinary model reservation slots without completing either
  // upload. This distinguishes durable timeout cleanup from a hidden slot leak.
  const replacements=Array.from({length:2},()=>task('job.create',{...manifest,idempotency:randomUUID()}));
  assert.equal(new Set(replacements.map(value=>value.job)).size,2);
  for(const replacement of replacements){
   assert.equal(replacement.state,'reserved');assert.notEqual(replacement.job,job);
   assert.equal(task('job.cancel',{job:replacement.job}).lease.revoked,true);
  }
  await until(()=>replacements.every(({job:id})=>task('job.status',{job:id}).state==='removed'));
  await replaceManager(status.epoch);
  const restored=task('job.status',{job});
  assert.equal(restored.state,'removed');assert.equal(restored.lease.revoked,true);assert.equal(restored.event,undefined);
  const replay=task('job.create',manifest);
  assert.equal(replay.job,job);assert.equal(replay.state,'removed');assert.equal(replay.lease.deadline_at,deadline);
  assert.equal(task('job.create',{phase:'end',job}).state,'removed');
  const summary=JSON.parse(command(cli,['--state',state,'status'],3000));
  assert.equal(summary.worker_reservations,0);assert.equal(summary.unresolved_requests,0);assert.equal(posts,0);
  manager.kill('SIGTERM');await until(()=>exited(manager),5000);assert.equal(manager.exitCode,0);
  const db=new DatabaseSync(join(state,'state.sqlite'),{readOnly:true});
  try {
   for(const table of ['inference','request_history','worker_launches','worker_grants']){
    const count=db.prepare(`SELECT count(*) AS count FROM ${table} WHERE job=?`);
    for(const id of [job,...replacements.map(value=>value.job)])assert.equal(count.get(id).count,0);
   }
  } finally {db.close();}
  return {scenario,expired_without_end:true,late_end_status_only:true,restart_checked:true,reservation_slots_reused:2,durable_dispatch_rows:0,state:restored.state,mock_model_posts:0,worker_slots_after_completion:0};
 }
 if(scenario==='upload_restart'){
  assert.equal(posts,0);await replaceManager(status.epoch);
  let restored;
  await until(()=>{restored=task('job.status',{job});return restored.state==='removed';});
  assert.equal(restored.lease.revoked,true);assert.equal(restored.unresolved_managed_requests,0);assert.equal(restored.event,undefined);
  const replay=task('job.create',manifest);assert.equal(replay.job,job);assert.equal(replay.state,'removed');assert.equal(replay.lease.revoked,true);
  const acknowledgement=task('job.create',{phase:'end',job});assert.equal(acknowledgement.state,'removed');assert.equal(acknowledgement.lease.deadline_at,deadline);
  // Replacement is deliberately not enrolled. Free local capacity and a
  // successful status-only replay cannot restore its admission authority.
  task('job.create',{...manifest,idempotency:randomUUID()},'native_unsupported');
  assert.equal(posts,0);const clean=JSON.parse(command(cli,['--state',state,'status'],3000));
  assert.equal(clean.worker_reservations,0);assert.equal(clean.unresolved_requests,0);
  return {scenario,restart_checked:true,input_bytes:data.length,input_chunks:chunks,partial_upload:true,replay_status_only:true,fresh_reservation_refused_without_enrollment:true,state:restored.state,mock_model_posts:posts,worker_slots_after_completion:0};
 }
 if(['invalid_history','replaced_source','duplicate_chunk','digest_mismatch'].includes(scenario)){
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
  let restartChecked=false;
  if(scenario==='digest_mismatch'){
   await replaceManager(status.epoch);
   const restored=task('job.status',{job});
   assert.equal(restored.state,'removed');assert.equal(restored.lease.revoked,true);
   assert.equal(restored.unresolved_managed_requests,0);assert.equal(restored.event,undefined);
   assert.equal(task('job.create',manifest).job,job);assert.equal(posts,0);
   restartChecked=true;
  }
  return {scenario,state:final.state,restart_checked:restartChecked,mock_model_posts:posts,worker_attempts:0,worker_slots_after_completion:0};
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
 // The synchronous CLI may consume the terminal event before Node drains
 // the separate mock process's stdout. Wait for the report, never replay.
 await until(()=>{if(streamFailure)throw streamFailure;assert(!exited(mock),`Mock exited before reporting ${scenario}`);return posts>=1;},3000);
 assert.equal(posts,1,`Expected exactly one mock POST for ${scenario}`);assert.equal(final.lease.deadline_at,deadline);assert.equal(final.lease.revoked,true);
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
} catch(error) {
 caseFailed=true;throw error;
} finally {
 if(manager&&!exited(manager))manager.kill('SIGTERM');
 try {await until(()=>children.filter(child=>child!==mock).every(exited),5000);}
 finally {if(mock&&!exited(mock))mock.stdin.end();await until(()=>!mock||mockClosed,5000);}
 if(!caseFailed){
  if(streamFailure)throw streamFailure;
  assert.equal(buffered,'',`Truncated final mock report for ${scenario}`);
  const expected=['complete','cancel','unavailable','unicode'].includes(scenario)?1:0;
  assert.equal(posts,expected,`Unexpected final mock POST count for ${scenario}`);
 }
}
}
const records=[];
for(const scenario of ['complete','cancel','unavailable','upload_restart','unicode','invalid_history','replaced_source','duplicate_chunk','digest_mismatch','reserved_capacity','upload_timeout'])records.push(await modelCase(scenario));
const receipt={scope:'normal_cli_model_job_completion_cancellation_and_service_failure',records,real_model_requests:0,runtime_actions:0,native_acceptance:false,cli_sha256:sha(readFileSync(cli)),manager_sha256:sha(readFileSync(binary))};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({ok:true,directory,...receipt}));
