#!/usr/bin/env node
// Ordinary restart/target-instance correctness with two private empty-model
// source processes. No installed service, model load, native admission or fault injection.
import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {createHash,randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewJSON,nativeReviewActivity} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
const capsule=verifyNativeReview(args[2],args[4]),directory=mkdtempSync('/private/tmp/f9-native-instance-');
const observer=path.join(directory,'observe');
execFileSync('/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'-O2','-o',observer],{timeout:30000,stdio:'pipe'});
const reservation=createServer();await new Promise((ok,no)=>{reservation.once('error',no);reservation.listen(0,'127.0.0.1',ok);});
const port=reservation.address().port;await new Promise(ok=>reservation.close(ok));
const key=randomBytes(32).toString('hex'),profile=path.join(root,'tests/fixtures/platform/native-model-review.sb');
let active,attempts=0,peak=0;const started=performance.now(),deadline=started+20000;
function ended(entry){return (entry.launchError&&!entry.child.pid)||entry.child.exitCode!==null||entry.child.signalCode!==null;}
function identity(entry){
 const result=spawnSync(observer,[String(entry.child.pid)],{encoding:'utf8',timeout:1000,maxBuffer:2048});assert.equal(result.status,0);
 const value=JSON.parse(result.stdout);assert(value.pid===entry.child.pid&&value.uid===process.getuid());
 if(entry.original)assert.equal(value.start,entry.original.start);else entry.original=value;
 return value;
}
function observe(entry){const value=identity(entry);peak=Math.max(peak,value.resident,value.footprint);assert(peak<=256*2**20);return value;}
function signal(entry,value){if(ended(entry)||!entry.original)return;try{if(identity(entry).start===entry.original.start)entry.child.kill(value);}catch{}}
async function stop(entry){
 if(!entry)return;
 const end=performance.now()+3000;signal(entry,'SIGTERM');
 while(!ended(entry)&&performance.now()<end-1000)await delay(10);
 if(!ended(entry))signal(entry,'SIGKILL');
 while(!ended(entry)&&performance.now()<end)await delay(10);
 if(!ended(entry)){entry.child.unref();entry.child.stdout.destroy();entry.child.stderr.destroy();throw Error('Owned source process not reaped; retain state');}
}
async function request(route,{method='GET',instance}={}){
 if(method==='POST')attempts++;
 const response=await fetch('http://127.0.0.1:'+port+route,{method,redirect:'error',signal:AbortSignal.timeout(1000),
  headers:{Authorization:'Bearer '+key,...(instance?{'X-Fios-Native-Instance':instance}:{}),...(method==='POST'?{'Content-Type':'application/json'}:{})},
  ...(method==='POST'?{body:'null'}:{})});
 return {status:response.status,value:await nativeReviewJSON(response,16384)};
}
async function start(index){
 const home=path.join(directory,'home-'+index);mkdirSync(home,{mode:0o700});const models=path.join(home,'empty-models');mkdirSync(models,{mode:0o700});
 const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:home,XDG_CACHE_HOME:path.join(home,'cache'),LANG:'C',LC_ALL:'C',
  FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_INSTANCE_KEY:key};
 const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',profile,
  capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--api-key-env','FIOS_SOURCE_INSTANCE_KEY','--api-key-strict'],
  {cwd:home,env,stdio:['ignore','pipe','pipe']});
 const entry={child,launchError:false};child.once('error',()=>{entry.launchError=true;});active=entry;let size=0;
 for(const pipe of [child.stdout,child.stderr])pipe.on('data',part=>{size+=part.length;if(size>128*1024)signal(entry,'SIGTERM');});
 const until=Math.min(deadline,performance.now()+5000);let healthy=false;
 while(performance.now()<until&&!healthy){
  assert(!entry.launchError&&!ended(entry));try{observe(entry);const health=await request('/health');healthy=health.status===200&&health.value.status==='ok';}catch{await delay(25);}
 }
 assert(healthy,'Private empty-model source startup deadline');
 const catalog=await request('/v1/models');assert.equal(catalog.status,200);assert.deepEqual(catalog.value.data,[]);
 const activity=await request('/v1/fios/activity');assert.equal(activity.status,200);
 return {entry,instance:nativeReviewActivity(activity.value).instance};
}
try{
 const first=await start(1);await stop(first.entry);active=null;
 const second=await start(2);assert.notEqual(second.instance,first.instance);
 const stale=await request('/v1/chat/completions',{method:'POST',instance:first.instance});
 assert.equal(stale.status,409,'An earlier native instance must refuse before model resolution');
 assert.equal(stale.value.error?.type,'native_instance_changed');
 const current=await request('/v1/chat/completions',{method:'POST',instance:second.instance});
 const legacy=await request('/v1/chat/completions',{method:'POST'});
 assert([400,404,503].includes(legacy.status));
 if(capsule.receipt.declared_inputs.native_bound_target_json_version===1){
  assert.equal(current.status,400);assert.equal(current.value.error?.type,'invalid_request_error');
 }else if(capsule.receipt.declared_inputs.native_bound_local_target_guard_version===1){
  assert.equal(current.status,404);assert.equal(current.value.error?.type,'native_target_not_found');
 }else{
  assert.equal(current.status,legacy.status,'The current instance must reach ordinary input validation');
  assert.equal(current.value.error?.type,legacy.value.error?.type);
 }
 assert.deepEqual((await request('/v1/models')).value.data,[]);observe(second.entry);
 await stop(second.entry);active=null;assert(performance.now()<deadline);
 const outcome={ok:true,source_fixture_only:true,capsule_sha256:args[4],distinct_actual_instances:true,same_loopback_endpoint:true,stale_instance_status:409,current_instance_status:current.status,legacy_status:legacy.status,
  chat_endpoint_post_attempts:attempts,model_loads:0,native_inference:false,installed_service_actions:0,fault_injection:false,native_authority:false,
  observed_process_bytes:peak,elapsed_ms:Math.round(performance.now()-started),observer_source_sha256:createHash('sha256').update(readFileSync(path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'))).digest('hex'),directory};
 writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(outcome)+'\n',{mode:0o600});console.log(JSON.stringify(outcome));
}finally{await stop(active);}
