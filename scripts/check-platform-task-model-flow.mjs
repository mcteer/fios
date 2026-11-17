#!/usr/bin/env node
// Normal CLI completion, owner cancellation and service-unavailable reporting; local MOCK only.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readdirSync,copyFileSync,chmodSync,readFileSync,writeFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
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
function task(operation,payload){
 const id=randomUUID(),result=spawnSync(cli,['--state',state,'task'],{cwd:root,encoding:'utf8',timeout:3000,input:JSON.stringify({version:1,id,operation,payload:{...payload,owner:token}})});
 assert.equal(result.status,0,'Normal CLI task request failed');const reply=JSON.parse(result.stdout);assert.equal(reply.ok,true);assert.equal(reply.id,id);assert(reply.result);return reply.result;
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
 const data=Buffer.from(JSON.stringify([{role:'user',content:scenario==='complete'?'ordinary CLI text 👋\n'.repeat(2200):scenario==='cancel'?'ordinary delayed reply':'ordinary unavailable reply'}]));
 const created=task('job.create',{phase:'begin',idempotency:randomUUID(),kind:'model',length:data.length,sha256:sha(data),lifetime:60000,model:'fixture/model',image:null,memory:0,cpus:0});
 assert.equal(created.state,'reserved');const job=created.job,deadline=created.lease.deadline_at;
 const observed=task('job.status',{job});assert.equal(observed.lease.expires_at,created.lease.expires_at);
 await delay(25);const renewed=task('job.renew',{job});assert(renewed.lease.expires_at>created.lease.expires_at);assert.equal(renewed.lease.deadline_at,deadline);
 let chunks=0;for(let offset=0;offset<data.length;offset+=32768){task('job.create',{phase:'chunk',job,index:chunks++,data:data.subarray(offset,offset+32768).toString('base64')});}
 task('job.create',{phase:'end',job});
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
 if(scenario==='complete'){assert.equal(text,'MOCK_ONLY');assert.equal(terminal,'complete');}
 if(scenario==='unavailable'){assert.equal(text,'');assert.equal(terminal,'failed');assert.equal(failureCode,'upstream_http');}
 assert.equal(posts,1);assert.equal(final.lease.deadline_at,deadline);assert.equal(final.lease.revoked,true);
 await until(()=>JSON.parse(command(cli,['--state',state,'status'],3000)).worker_reservations===0);
 assert.equal(final.unresolved_managed_requests,1);
 return {scenario,input_bytes:data.length,input_chunks:chunks,output_events:ordinal,terminal:terminal??null,failure_code:failureCode??null,state:final.state,cancelled_while_running:wasRunning,lease_read_did_not_extend:true,renewal_extended_expiry:true,deadline_unchanged:true,mock_model_posts:posts,worker_slots_after_completion:0};
} finally {
 if(manager&&!exited(manager))manager.kill('SIGTERM');if(mock&&!exited(mock))mock.stdin.end();
 await until(()=>children.every(exited),5000);
}
}
const records=[];
for(const scenario of ['complete','cancel','unavailable'])records.push(await modelCase(scenario));
const receipt={scope:'normal_cli_model_job_completion_cancellation_and_service_failure',records,real_model_requests:0,runtime_actions:0,native_acceptance:false,cli_sha256:sha(readFileSync(cli)),manager_sha256:sha(readFileSync(binary))};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({ok:true,directory,...receipt}));
