#!/usr/bin/env node
// Private empty-catalog native HTTP/control -> actual Swift client/journal.
// No real inference, installed operation or native admission/completion grant.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,readdirSync,copyFileSync} from 'node:fs';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {createServer} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import path from 'node:path';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewJSON} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
const capsule=verifyNativeReview(args[2],args[4]),review=JSON.parse(readFileSync(path.join(args[2],'review.json')));
assert.equal(review.declared_inputs.native_handoff_version,1,'Capsule has no reviewed handoff interface');
const directory=mkdtempSync('/private/tmp/f9-handoff-'),home=path.join(directory,'home');mkdirSync(home,{mode:0o700});
const models=path.join(home,'empty-models');mkdirSync(models,{mode:0o700});
const sha=file=>createHash('sha256').update(readFileSync(file)).digest('hex'),core='platform/studio/Sources/StudioCore';
const files=[...readdirSync(path.join(root,core)).filter(n=>n.endsWith('.swift')).sort().map(n=>core+'/'+n),
 'platform/studio/Tests/StudioCoreTests/NativeHandoffClient.swift.fixture','platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture',
 'platform/studio/Sources/CSQLite/shim.h','platform/studio/Sources/CSQLite/module.modulemap','tests/fixtures/platform/native-model-review.sb','scripts/check-platform-native-handoff.mjs'];
const capture=()=>Object.fromEntries(files.map(file=>[file,sha(path.join(root,file))])),inputs=capture(),records=[];
const env={PATH:'/usr/bin:/bin',HOME:home,LANG:'C',LC_ALL:'C'};
function run(name,program,argv,timeout=180000){
 const r=spawnSync(program,argv,{env,encoding:'utf8',timeout,maxBuffer:2<<20});
 const log=path.join(directory,name+'.log');writeFileSync(log,(r.stdout??'')+(r.stderr??''),{mode:0o600});
 records.push({name,status:r.status,signal:r.signal,log_sha256:sha(log)});
 assert(!r.error&&r.status===0,name+' failed; retain '+directory);return r.stdout.trim();
}
const client=path.join(directory,'client'),swift=path.join(directory,'Client.swift'),observer=path.join(directory,'observe');
copyFileSync(path.join(root,'platform/studio/Tests/StudioCoreTests/NativeHandoffClient.swift.fixture'),swift);
run('swift-build','/usr/bin/swiftc',['-swift-version','6','-warnings-as-errors','-j2','-I',path.join(root,'platform/studio/Sources/CSQLite'),
 ...files.filter(n=>n.startsWith(core+'/')).map(n=>path.join(root,n)),swift,'-o',client]);
run('observer-build','/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'-O2','-o',observer],30000);
const reservation=createServer();await new Promise((ok,no)=>{reservation.once('error',no);reservation.listen(0,'127.0.0.1',ok)});
const port=reservation.address().port;await new Promise(ok=>reservation.close(ok));
const key=randomBytes(32).toString('hex'),profile=path.join(root,'tests/fixtures/platform/native-model-review.sb');
const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',profile,
 capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--api-key-env','FIOS_SOURCE_INSTANCE_KEY','--api-key-strict'],
 {cwd:home,env:{...env,XDG_CACHE_HOME:path.join(home,'cache'),FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_INSTANCE_KEY:key},stdio:['ignore','pipe','pipe']});
let original,peak=0,bytes=0,error,attempts=0;const deadline=performance.now()+30000;
child.once('error',()=>{error=Error('Private native launch failed')});
for(const pipe of [child.stdout,child.stderr])pipe.on('data',part=>{bytes+=part.length;if(bytes>128*1024)error=Error('Private diagnostic bound')});
const exited=()=>child.exitCode!==null||child.signalCode!==null;
function identity(){
 const r=spawnSync(observer,[String(child.pid)],{env,encoding:'utf8',timeout:1000,maxBuffer:2048});assert.equal(r.status,0);
 const value=JSON.parse(r.stdout);assert.equal(value.uid,process.getuid());
 if(original)assert.equal(value.start,original.start);else original=value;return value;
}
function observe(){
 const value=identity();
 peak=Math.max(peak,value.resident,value.footprint);assert(peak<=256*2**20);return value;
}
function signal(value){if(exited()||!original)return;try{if(identity().start===original.start)child.kill(value)}catch{}}
async function request(route,{method='GET',headers={},body}={}){
 if(method==='POST')attempts++;
 const response=await fetch('http://127.0.0.1:'+port+route,{method,redirect:'error',signal:AbortSignal.timeout(2000),
  headers:{Authorization:'Bearer '+key,...headers},...(body!==undefined?{body}:{})});
 return {status:response.status,value:await nativeReviewJSON(response,65536)};
}
const unixPolicy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
const state=path.join(directory,'state'),socket=path.join(home,'.fios-native-control/control.sock');
function invoke(step,job,instance){assert(performance.now()<deadline);observe();return run(step+'-'+job,'/usr/bin/sandbox-exec',['-p',unixPolicy,client,state,String(child.pid),capsule.binary,socket,job,instance,step],8000)}
function parseRegistration(output){const parts=output.split(' ');assert(parts.length===2&&/^[a-f0-9]{64}$/.test(parts[0])&&/^[1-9][0-9]{0,19}$/.test(parts[1]));assert(BigInt(parts[1])<=18446744073709551615n);return {id:parts[0],root:parts[1]}}
try {
 let healthy=false;const startDeadline=Math.min(deadline,performance.now()+10000);
 while(performance.now()<startDeadline&&!healthy){assert(!error&&!exited());try{observe();healthy=(await request('/health')).status===200}catch{await delay(25)}}
 assert(healthy,'Private startup deadline');assert.deepEqual((await request('/v1/models')).value.data,[]);
 const activity=await request('/v1/fios/activity'),instance=activity.value.source_instance;assert.equal(activity.value.coverage,'unknown');assert.match(instance,/^[a-f0-9]{32}$/);
 const cancelled=randomUUID(),cancelRegistration=parseRegistration(invoke('register',cancelled,instance));
 invoke('cancel',cancelled,instance);
 const headers=value=>({'Content-Type':'application/json','X-Fios-Native-Instance':instance,'X-Fios-Request-ID':value.id,'X-Fios-Handoff-Root':value.root});
 const body=JSON.stringify({model:'fixture/missing-model',messages:[]});
 const late=await request('/v1/chat/completions',{method:'POST',headers:headers(cancelRegistration),body});
 assert.equal(late.status,409);assert.equal(late.value.error.type,'native_handoff_unavailable');
 const consumed=randomUUID(),consumeRegistration=parseRegistration(invoke('register',consumed,instance));
 const accepted=await request('/v1/chat/completions',{method:'POST',headers:headers(consumeRegistration),body});
 assert.equal(accepted.status,404);assert.equal(accepted.value.error.type,'native_target_not_found');
 invoke('consumed',consumed,instance);assert.equal(attempts,2);observe();assert.deepEqual(capture(),inputs);
 const result={scope:'actual_empty_native_registered_HTTP_handoff_Swift_journal_not_native_completion_authority',inputs,records,
  capsule_receipt_sha256:args[4],source_instance:instance,stages:4,original_root_established_before_POST:true,cancelled_original_late_POST_denied:true,
  fast_rejection_preserves_original_root:true,independent_uncertain_claims_retained:2,private_rejected_HTTP_POSTs:attempts,real_model_POSTs:0,models:0,
  peak_native_process_bytes:peak,native_authority:false,installed:false,activation:false,inputs_unchanged:true};
 writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(result,null,2)+'\n',{mode:0o600});console.log(JSON.stringify({directory,receipt_sha256:sha(path.join(directory,'receipt.json')),stages:4,native_authority:false}));
} finally {
 signal('SIGTERM');let end=performance.now()+2000;while(!exited()&&performance.now()<end)await delay(10);
 if(!exited())signal('SIGKILL');end=performance.now()+1000;while(!exited()&&performance.now()<end)await delay(10);
 if(!exited()){child.unref();child.stdout.destroy();child.stderr.destroy();throw Error('Private source reap unknown; retain '+directory)}
}
