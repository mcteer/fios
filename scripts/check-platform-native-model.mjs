#!/usr/bin/env node
// Administrative source experiment. No production/native enrollment or task
// permission is issued. Plan/check never load a model. Run requires separate
// explicit operator approval; ordinary Fios inference still uses its harness.
import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,openSync,readSync,closeSync,fstatSync,lstatSync,readdirSync,realpathSync,mkdirSync,mkdtempSync,symlinkSync,chmodSync,fsyncSync,renameSync,constants} from 'node:fs';
import {homedir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {createServer} from 'node:net';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewIntent,nativeReviewHTTPFailure} from './lib/platform-native-review-intent.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
nativeReviewIntent(args);
const ID='mlx-community/gemma-4-e4b-it-4bit',MODEL=path.join(homedir(),'.mlx-serve/models',ID);
const LIMITS={context_tokens:512,output_tokens:8,max_concurrent:1,model_posts:1,request_ms:90000,work_ms:120000,cleanup_ms:7000,memory_abort_bytes:12*2**30};
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const sha=b=>createHash('sha256').update(b).digest('hex');
function runnerInputs(){return Object.fromEntries(['scripts/check-platform-native-model.mjs','scripts/lib/platform-native-review.mjs','scripts/lib/platform-native-review-intent.mjs','platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'].map(name=>[name,sha(readFileSync(path.join(root,name)))]));}
function privateParent(file){const p=realpathSync(path.dirname(file)),s=lstatSync(p);assert(path.dirname(file)===p&&s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o077)===0);return p;}
function json(file,maximum=65536){const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);try{const s=fstatSync(fd);assert(s.isFile()&&s.nlink===1&&s.size>0&&s.size<=maximum);const bytes=Buffer.alloc(s.size);let n=0;while(n<bytes.length){const c=readSync(fd,bytes,n,bytes.length-n,null);assert(c>0);n+=c;}return {bytes,value:JSON.parse(bytes.toString('utf8'))};}finally{closeSync(fd);}}
function durableNew(file,bytes,mode=0o400){const fd=openSync(file,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,mode);try{writeFileSync(fd,bytes);fsyncSync(fd);}finally{closeSync(fd);}const parent=openSync(path.dirname(file),constants.O_RDONLY);try{fsyncSync(parent);}finally{closeSync(parent);}}
function fingerprint(file){const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);try{const a=fstatSync(fd);assert(a.isFile()&&a.nlink===1&&a.size>0&&a.size<=8*2**30&&(a.mode&0o022)===0);const hash=createHash('sha256'),b=Buffer.alloc(65536);let count=0;for(;;){const n=readSync(fd,b,0,b.length,null);if(!n)break;count+=n;assert(count<=a.size);hash.update(b.subarray(0,n));}const z=fstatSync(fd),named=lstatSync(file);for(const k of ['dev','ino','size','mode','mtimeMs','ctimeMs'])assert(a[k]===z[k]&&a[k]===named[k]);assert(count===a.size);return {bytes:count,sha256:hash.digest('hex'),dev:a.dev,ino:a.ino,mtime:a.mtimeMs,ctime:a.ctimeMs};}finally{closeSync(fd);}}
if(args[0]==='--plan'){
 assert(args.length===7&&args[1]==='--capsule'&&args[3]==='--sha256'&&args[5]==='--output'&&path.isAbsolute(args[2])&&path.isAbsolute(args[6]));
 const capsule=verifyNativeReview(args[2],args[4]),parent=privateParent(args[6]);
 assert(realpathSync(MODEL)===MODEL);const config=json(path.join(MODEL,'config.json'),1<<20).value;assert(config.model_type==='gemma4');
 const modelFiles=readdirSync(MODEL).filter(n=>n.endsWith('.safetensors')||['config.json','tokenizer.json','tokenizer_config.json','generation_config.json','processor_config.json'].includes(n)).sort();
 assert(modelFiles.some(n=>n.endsWith('.safetensors'))&&modelFiles.length<=32);
 const files=Object.fromEntries(modelFiles.map(n=>[n,fingerprint(path.join(MODEL,n))]));assert(Object.values(files).reduce((n,f)=>n+f.bytes,0)<=8*2**30);
 const nonce=randomUUID(),observer=path.join(parent,'observe-'+nonce);
 execFileSync('/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'-O2','-o',observer],{timeout:30000,stdio:'pipe',env:{PATH:'/usr/bin:/bin',HOME:parent,LANG:'C',LC_ALL:'C'}});chmodSync(observer,0o500);
 const self=JSON.parse(execFileSync(observer,[String(process.pid)],{encoding:'utf8',timeout:1000}));assert(self.pid===process.pid&&self.uid===process.getuid());
 const plan={version:1,runner_inputs:runnerInputs(),purpose:'private_gemma4_source_experiment',nonce,created:Date.now(),capsule:capsule.directory,capsule_sha256:args[4],model:ID,model_directory:MODEL,model_files:files,limits:LIMITS,observer,observer_sha256:sha(readFileSync(observer)),profile_sha256:sha(readFileSync(path.join(root,'tests/fixtures/platform/native-model-review.sb'))),native_admission_authority:false,requires_explicit_inference_opt_in:true};
 const bytes=Buffer.from(JSON.stringify(plan)+'\n');writeFileSync(args[6],bytes,{flag:'wx',mode:0o400});const fd=openSync(args[6],'r');try{fsyncSync(fd);}finally{closeSync(fd);}
 console.log(JSON.stringify({planning_only:true,native_inference:false,model:ID,model_weight_bytes:Object.entries(files).filter(([n])=>n.endsWith('.safetensors')).reduce((n,[,f])=>n+f.bytes,0),plan:args[6],plan_sha256:sha(bytes),limits:LIMITS,check:[process.execPath,fileURLToPath(import.meta.url),'--check','--plan',args[6],'--sha256',sha(bytes)],approval_command:[process.execPath,fileURLToPath(import.meta.url),'--run','--plan',args[6],'--sha256',sha(bytes),'--allow-native-inference']}));
 process.exit(0);
}
const check=args[0]==='--check';assert((check&&args.length===5)||(!check&&args[0]==='--run'&&args.length===6&&args[5]==='--allow-native-inference'));
assert(args[1]==='--plan'&&args[3]==='--sha256'&&path.isAbsolute(args[2]));const parent=privateParent(args[2]),document=json(args[2]);assert(sha(document.bytes)===args[4]);const plan=document.value;assert(!plan.synthetic_resource_fixture||check,'Synthetic observations cannot be used for inference');assert.deepEqual(plan.runner_inputs,runnerInputs());
assert(plan.version===1&&plan.purpose==='private_gemma4_source_experiment'&&plan.model===ID&&plan.model_directory===MODEL&&plan.native_admission_authority===false&&plan.requires_explicit_inference_opt_in===true&&JSON.stringify(plan.limits)===JSON.stringify(LIMITS));
assert(Date.now()>=plan.created-1000&&Date.now()-plan.created<=24*3600000);const capsule=verifyNativeReview(plan.capsule,plan.capsule_sha256);
assert(path.dirname(plan.observer)===parent&&lstatSync(plan.observer).isFile()&&!lstatSync(plan.observer).isSymbolicLink()&&sha(readFileSync(plan.observer))===plan.observer_sha256);
const profile=path.join(root,'tests/fixtures/platform/native-model-review.sb');assert(sha(readFileSync(profile))===plan.profile_sha256);
const directory=mkdtempSync(check?'/private/tmp/f9-model-check-':'/private/tmp/f9-model-run-');chmodSync(directory,0o700);
if(!check){for(const [name,expected]of Object.entries(plan.model_files))assert.deepEqual(fingerprint(path.join(MODEL,name)),expected);durableNew(args[2]+'.consumed',JSON.stringify({nonce:plan.nonce,directory,at:Date.now()})+'\n');}
const home=path.join(directory,'home');mkdirSync(home,{mode:0o700});const models=path.join(home,'models');mkdirSync(models,{mode:0o700});mkdirSync(path.join(home,'tmp'),{mode:0o700});
if(!check){mkdirSync(path.join(models,'mlx-community'),{mode:0o700});symlinkSync(MODEL,path.join(models,ID),'dir');}
const reservation=createServer();await new Promise((ok,no)=>{reservation.once('error',no);reservation.listen(0,'127.0.0.1',ok);});const port=reservation.address().port;await new Promise(ok=>reservation.close(ok));
const key=randomBytes(32).toString('hex'),env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:path.join(home,'tmp'),XDG_CACHE_HOME:path.join(home,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_MODEL_KEY:key};
const receipt={source_fixture_only:true,synthetic_resource_fixture:plan.synthetic_resource_fixture===true,model:check?null:ID,native_inference:check?false:null,inference_requested:!check,actual_model_posts:0,coverage:'unknown',native_quiescence:'unproven',process_reaped:false,peak_resident:0,peak_footprint:0};
function save(){const temporary=path.join(directory,'.result-'+randomUUID());durableNew(temporary,JSON.stringify(receipt)+'\n',0o600);renameSync(temporary,path.join(directory,'result.json'));const fd=openSync(directory,constants.O_RDONLY);try{fsyncSync(fd);}finally{closeSync(fd);}}save();
const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',profile,capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--no-vision','--ctx-size','512','--max-concurrent','1','--api-key-env','FIOS_SOURCE_MODEL_KEY','--api-key-strict'],{env,cwd:home,stdio:['ignore','pipe','pipe']});
let original,output=0,failed,timer,postsDone=false,stage='owned_identity';
function ended(){return child.exitCode!==null||child.signalCode!==null;}
function observe(){const r=spawnSync(plan.observer,[String(child.pid)],{encoding:'utf8',timeout:1000,maxBuffer:1024,env:{PATH:'/usr/bin:/bin',LANG:'C'}});assert(r.status===0);const p=JSON.parse(r.stdout);assert(p.pid===child.pid&&p.uid===process.getuid()&&/^\d+:\d+$/.test(p.start)&&Number.isSafeInteger(p.resident)&&Number.isSafeInteger(p.footprint));return p;}
function signalOwned(signal){if(ended())return;try{const p=observe();if(original&&p.start===original.start)child.kill(signal);}catch{}}
for(const pipe of [child.stdout,child.stderr])pipe.on('data',chunk=>{output+=chunk.length;if(output>128*1024){failed='diagnostic_output_limit';signalOwned('SIGTERM');}});
child.once('error',()=>{failed='launch_failed';});const began=performance.now();
async function get(route){const r=await fetch('http://127.0.0.1:'+port+route,{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(2000)});assert(r.ok);const bytes=await r.arrayBuffer();assert(bytes.byteLength<65536);return JSON.parse(Buffer.from(bytes).toString('utf8'));}
try{
 const identityDeadline=performance.now()+2000;while(!original&&performance.now()<identityDeadline&&!ended()){try{original=observe();}catch{await delay(20);}}assert(original,'Owned process identity unavailable');receipt.original_process={pid:original.pid,uid:original.uid,start:original.start};receipt.peak_resident=original.resident;receipt.peak_footprint=original.footprint;if(Math.max(original.resident,original.footprint)>LIMITS.memory_abort_bytes){failed='memory_abort_threshold';signalOwned('SIGKILL');throw Error('Resource threshold');}save();stage='resource_monitor';
 timer=setInterval(()=>{if(ended())return;try{const p=observe();assert(p.start===original.start);receipt.peak_resident=Math.max(receipt.peak_resident,p.resident);receipt.peak_footprint=Math.max(receipt.peak_footprint,p.footprint);if(Math.max(p.resident,p.footprint)>LIMITS.memory_abort_bytes){failed='memory_abort_threshold';signalOwned('SIGKILL');}}catch{failed='resource_identity_unknown';signalOwned('SIGTERM');}if(performance.now()-began>LIMITS.work_ms){failed='overall_deadline';signalOwned('SIGKILL');}},500);
 stage='readiness';let ready=false;for(let i=0;i<200&&!ready;i++){assert(!ended()&&!failed);try{ready=(await get('/health')).status==='ok';}catch{await delay(25);}}assert(ready,'Private source readiness unavailable');
 stage='catalog';const before=await get('/v1/models');assert(Array.isArray(before.data));assert(before.data.every(m=>!m.loaded&&m.state!=='ready'),'Unexpected preloaded model');
 stage='diagnostic';const diagnostic=await get('/v1/fios/activity');assert(diagnostic.coverage==='unknown');
 if(check){assert(before.data.length===0);receipt.result='empty_model_profile_and_identity_passed';}
 else{
  assert(before.data.some(m=>m.id===ID),'Exact selected model not advertised');receipt.native_uncertainty=true;receipt.native_inference=null;receipt.inference_attempted=true;receipt.actual_model_posts=1;save();
  stage='model_request';const response=await fetch('http://127.0.0.1:'+port+'/v1/chat/completions',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({model:ID,messages:[{role:'user',content:'Reply with one word: ready.'}],max_tokens:8,temperature:0,stream:true,stream_options:{include_usage:true}}),signal:AbortSignal.timeout(LIMITS.request_ms)});
  if(!response.ok){let bytes=0,body='';for await(const chunk of response.body){bytes+=chunk.length;assert(bytes<=16384);body+=Buffer.from(chunk).toString('utf8');}let value;try{value=JSON.parse(body);}catch{}receipt.http_failure=nativeReviewHTTPFailure(response.status,value);throw Error('Native model request refused');}stage='model_stream';let buffer='',bytes=0,done=false,deltas=0,completionTokens=null;
  for await(const chunk of response.body){bytes+=chunk.length;assert(bytes<=65536&&!failed);buffer+=Buffer.from(chunk).toString('utf8');let at;while((at=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,at).trim();buffer=buffer.slice(at+1);if(!line.startsWith('data:'))continue;const data=line.slice(5).trim();if(data==='[DONE]'){done=true;continue;}const value=JSON.parse(data);assert(!value.error);if(value.choices?.some(c=>['content','reasoning_content'].some(k=>typeof c.delta?.[k]==='string'&&c.delta[k].length>0)))deltas++;if(value.usage?.completion_tokens!==undefined){assert(Number.isSafeInteger(value.usage.completion_tokens)&&value.usage.completion_tokens>=0&&value.usage.completion_tokens<=8);completionTokens=value.usage.completion_tokens;}}}
  assert(done&&completionTokens!==null&&completionTokens>0);receipt.completion_tokens=completionTokens;receipt.delta_events=deltas;postsDone=true;receipt.native_inference=true;assert((await get('/v1/fios/activity')).coverage==='unknown');receipt.result='single_source_model_response_complete';receipt.generated_text_logged=false;
 }
 assert(!failed);receipt.elapsed_ms=Math.round(performance.now()-began);
}catch{receipt.result='failed';receipt.reason=failed||'review_'+stage+'_failure';process.exitCode=1;}
finally{
 clearInterval(timer);signalOwned('SIGTERM');let end=performance.now()+5000;while(!ended()&&performance.now()<end)await delay(25);if(!ended()){signalOwned('SIGKILL');end=performance.now()+2000;while(!ended()&&performance.now()<end)await delay(25);}
 receipt.process_reaped=ended();if(!receipt.process_reaped){receipt.result='failed';receipt.reason='owned_process_not_reaped';process.exitCode=1;child.unref();child.stdout.destroy();child.stderr.destroy();}
 receipt.response_complete=postsDone;save();console.log(JSON.stringify({...receipt,directory}));
}
