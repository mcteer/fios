#!/usr/bin/env node
// Administrative source experiment. No production/native enrollment or task
// permission is issued. Plan/check never load a model. Run uses an explicit
// finite invocation under standing operator inference authorization; ordinary
// Fios interface inference still uses its harness.
import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,openSync,readSync,closeSync,fstatSync,lstatSync,readdirSync,realpathSync,mkdirSync,mkdtempSync,symlinkSync,chmodSync,fsyncSync,renameSync,constants} from 'node:fs';
import {homedir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {createServer,createConnection} from 'node:net';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewIntent,nativeReviewHTTPFailure,nativeReviewJSON,nativeReviewActivity,nativeReviewModelInputs,nativeReviewLineage,nativeReviewComponents} from './lib/platform-native-review-intent.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
const intent=nativeReviewIntent(args),pair=intent.scenario==='same-model-pair',image=intent.scenario==='single-image';
const scenario=intent.scenario??'single-model',scenarioArgs=intent.scenario?['--scenario',scenario]:[];
if(intent.scenario)args.splice(-2,2);
const ID='mlx-community/gemma-4-e4b-it-4bit',MODEL=path.join(homedir(),'.mlx-serve/models',ID);
const LIMITS={context_tokens:512,output_tokens:8,max_concurrent:pair?2:1,model_posts:pair?2:1,request_ms:90000,work_ms:120000,cleanup_ms:7000,memory_abort_bytes:12*2**30};
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
function coreModelHost(){
 const read=(program,args)=>execFileSync(program,args,{encoding:'utf8',timeout:2000,maxBuffer:1024,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C'}}).trim();
 const host={local_hostname:read('/usr/sbin/scutil',['--get','LocalHostName']),
  memory_bytes:Number(read('/usr/sbin/sysctl',['-n','hw.memsize'])),cpu:read('/usr/sbin/sysctl',['-n','machdep.cpu.brand_string'])};
 assert(host.local_hostname==='fios-core'&&host.memory_bytes===24*2**30&&host.cpu.startsWith('Apple M4'),'This fixed small-model experiment runs only on fios-core');
 return host;
}
const executionHost=coreModelHost();

const sha=b=>createHash('sha256').update(b).digest('hex');
function runnerInputs(){return Object.fromEntries(['scripts/check-platform-native-model.mjs','scripts/lib/platform-native-review.mjs','scripts/lib/platform-native-review-intent.mjs','platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture','tests/fixtures/platform/native-image-64.png'].map(name=>[name,sha(readFileSync(path.join(root,name)))]));}
function privateParent(file){const p=realpathSync(path.dirname(file)),s=lstatSync(p);assert(path.dirname(file)===p&&s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o077)===0);return p;}
function json(file,maximum=65536){const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);try{const s=fstatSync(fd);assert(s.isFile()&&s.nlink===1&&s.size>0&&s.size<=maximum);const bytes=Buffer.alloc(s.size);let n=0;while(n<bytes.length){const c=readSync(fd,bytes,n,bytes.length-n,null);assert(c>0);n+=c;}return {bytes,value:JSON.parse(bytes.toString('utf8'))};}finally{closeSync(fd);}}
function durableNew(file,bytes,mode=0o400){const fd=openSync(file,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,mode);try{writeFileSync(fd,bytes);fsyncSync(fd);}finally{closeSync(fd);}const parent=openSync(path.dirname(file),constants.O_RDONLY);try{fsyncSync(parent);}finally{closeSync(parent);}}
function fingerprint(file){const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);try{const a=fstatSync(fd);assert(a.isFile()&&a.nlink===1&&a.size>0&&a.size<=8*2**30&&(a.mode&0o022)===0);const hash=createHash('sha256'),b=Buffer.alloc(65536);let count=0;for(;;){const n=readSync(fd,b,0,b.length,null);if(!n)break;count+=n;assert(count<=a.size);hash.update(b.subarray(0,n));}const z=fstatSync(fd),named=lstatSync(file);for(const k of ['dev','ino','size','mode','mtimeMs','ctimeMs'])assert(a[k]===z[k]&&a[k]===named[k]);assert(count===a.size);return {bytes:count,sha256:hash.digest('hex'),dev:a.dev,ino:a.ino,mtime:a.mtimeMs,ctime:a.ctimeMs};}finally{closeSync(fd);}}
if(args[0]==='--plan'){
 assert(args.length===7&&args[1]==='--capsule'&&args[3]==='--sha256'&&args[5]==='--output'&&path.isAbsolute(args[2])&&path.isAbsolute(args[6]));
 const capsule=verifyNativeReview(args[2],args[4]),parent=privateParent(args[6]);
 nativeReviewModelInputs(capsule.receipt.declared_inputs);
 assert(realpathSync(MODEL)===MODEL);const config=json(path.join(MODEL,'config.json'),1<<20).value;assert(config.model_type==='gemma4');
 if(image)assert(config.vision_config?.model_type==='gemma4_vision'&&config.vision_soft_tokens_per_image<=280);
 const modelFiles=readdirSync(MODEL).filter(n=>n.endsWith('.safetensors')||['config.json','tokenizer.json','tokenizer_config.json','generation_config.json','processor_config.json'].includes(n)).sort();
 assert(modelFiles.some(n=>n.endsWith('.safetensors'))&&modelFiles.length<=32);
 const files=Object.fromEntries(modelFiles.map(n=>[n,fingerprint(path.join(MODEL,n))]));assert(Object.values(files).reduce((n,f)=>n+f.bytes,0)<=8*2**30);
 const nonce=randomUUID(),observer=path.join(parent,'observe-'+nonce);
 execFileSync('/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'-O2','-o',observer],{timeout:30000,stdio:'pipe',env:{PATH:'/usr/bin:/bin',HOME:parent,LANG:'C',LC_ALL:'C'}});chmodSync(observer,0o500);
 const self=JSON.parse(execFileSync(observer,[String(process.pid)],{encoding:'utf8',timeout:1000}));assert(self.pid===process.pid&&self.uid===process.getuid());
 const plan={version:1,execution_host:executionHost,runner_inputs:runnerInputs(),purpose:'private_gemma4_source_experiment',scenario,nonce,created:Date.now(),capsule:capsule.directory,capsule_sha256:args[4],model:ID,model_directory:MODEL,model_files:files,limits:LIMITS,observer,observer_sha256:sha(readFileSync(observer)),profile_sha256:sha(readFileSync(path.join(root,'tests/fixtures/platform/native-model-review.sb'))),native_admission_authority:false,requires_explicit_inference_opt_in:true};
 const bytes=Buffer.from(JSON.stringify(plan)+'\n');writeFileSync(args[6],bytes,{flag:'wx',mode:0o400});const fd=openSync(args[6],'r');try{fsyncSync(fd);}finally{closeSync(fd);}
 console.log(JSON.stringify({planning_only:true,native_inference:false,execution_host:executionHost,model:ID,model_weight_bytes:Object.entries(files).filter(([n])=>n.endsWith('.safetensors')).reduce((n,[,f])=>n+f.bytes,0),plan:args[6],plan_sha256:sha(bytes),limits:LIMITS,check:[process.execPath,fileURLToPath(import.meta.url),'--check','--plan',args[6],'--sha256',sha(bytes),...scenarioArgs],run_command:[process.execPath,fileURLToPath(import.meta.url),'--run','--plan',args[6],'--sha256',sha(bytes),'--allow-native-inference',...scenarioArgs]}));
 process.exit(0);
}
const check=args[0]==='--check';assert((check&&args.length===5)||(!check&&args[0]==='--run'&&args.length===6&&args[5]==='--allow-native-inference'));
assert(args[1]==='--plan'&&args[3]==='--sha256'&&path.isAbsolute(args[2]));const parent=privateParent(args[2]),document=json(args[2]);assert(sha(document.bytes)===args[4]);const plan=document.value;assert.deepEqual(plan.execution_host,executionHost);assert(!plan.synthetic_resource_fixture||check,'Synthetic observations cannot be used for inference');assert.deepEqual(plan.runner_inputs,runnerInputs());
assert(plan.version===1&&plan.purpose==='private_gemma4_source_experiment'&&plan.scenario===scenario&&plan.model===ID&&plan.model_directory===MODEL&&plan.native_admission_authority===false&&plan.requires_explicit_inference_opt_in===true&&JSON.stringify(plan.limits)===JSON.stringify(LIMITS));
assert(Date.now()>=plan.created-1000&&Date.now()-plan.created<=24*3600000);const capsule=verifyNativeReview(plan.capsule,plan.capsule_sha256);nativeReviewModelInputs(capsule.receipt.declared_inputs);
assert(path.dirname(plan.observer)===parent&&lstatSync(plan.observer).isFile()&&!lstatSync(plan.observer).isSymbolicLink()&&sha(readFileSync(plan.observer))===plan.observer_sha256);
const profile=path.join(root,'tests/fixtures/platform/native-model-review.sb');assert(sha(readFileSync(profile))===plan.profile_sha256);
const directory=mkdtempSync(check?'/private/tmp/f9-model-check-':'/private/tmp/f9-model-run-');chmodSync(directory,0o700);
if(!check){for(const [name,expected]of Object.entries(plan.model_files))assert.deepEqual(fingerprint(path.join(MODEL,name)),expected);durableNew(args[2]+'.consumed',JSON.stringify({nonce:plan.nonce,directory,at:Date.now()})+'\n');}
const home=path.join(directory,'home');mkdirSync(home,{mode:0o700});const models=path.join(home,'models');mkdirSync(models,{mode:0o700});mkdirSync(path.join(home,'tmp'),{mode:0o700});
if(!check){mkdirSync(path.join(models,'mlx-community'),{mode:0o700});symlinkSync(MODEL,path.join(models,ID),'dir');}
const reservation=createServer();await new Promise((ok,no)=>{reservation.once('error',no);reservation.listen(0,'127.0.0.1',ok);});const port=reservation.address().port;await new Promise(ok=>reservation.close(ok));
const key=randomBytes(32).toString('hex'),env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:path.join(home,'tmp'),XDG_CACHE_HOME:path.join(home,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_MODEL_KEY:key};
const receipt={source_fixture_only:true,execution_host:executionHost,scenario,...(image?{image_input:{format:'png',width:64,height:64,sha256:sha(readFileSync(path.join(root,'tests/fixtures/platform/native-image-64.png')))}}:{}),synthetic_resource_fixture:plan.synthetic_resource_fixture===true,model:check?null:ID,native_inference:check?false:null,inference_requested:!check,model_post_attempts:0,actual_model_posts:0,coverage:'unknown',native_quiescence:'unproven',process_reaped:false,peak_resident:0,peak_footprint:0};
function save(){const temporary=path.join(directory,'.result-'+randomUUID());durableNew(temporary,JSON.stringify(receipt)+'\n',0o600);renameSync(temporary,path.join(directory,'result.json'));const fd=openSync(directory,constants.O_RDONLY);try{fsyncSync(fd);}finally{closeSync(fd);}}save();
const child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',profile,capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager',...(image?[]:['--no-vision']),'--ctx-size','512','--max-concurrent',String(LIMITS.max_concurrent),'--api-key-env','FIOS_SOURCE_MODEL_KEY','--api-key-strict'],{env,cwd:home,stdio:['ignore','pipe','pipe']});
const modelAbort=new AbortController();
let original,output=0,failed,timer,postsDone=false,stage='owned_identity';
function ended(){return child.exitCode!==null||child.signalCode!==null;}
function observe(){const r=spawnSync(plan.observer,[String(child.pid)],{encoding:'utf8',timeout:1000,maxBuffer:1024,env:{PATH:'/usr/bin:/bin',LANG:'C'}});assert(r.status===0);const p=JSON.parse(r.stdout);assert(p.pid===child.pid&&p.uid===process.getuid()&&/^\d+:\d+$/.test(p.start)&&Number.isSafeInteger(p.resident)&&Number.isSafeInteger(p.footprint));return p;}
function signalOwned(signal){if(ended())return;try{const p=observe();if(original&&p.start===original.start)child.kill(signal);}catch{}}
for(const pipe of [child.stdout,child.stderr])pipe.on('data',chunk=>{output+=chunk.length;if(output>128*1024){failed='diagnostic_output_limit';signalOwned('SIGTERM');}});
child.once('error',()=>{failed='launch_failed';});const began=performance.now();
async function get(route){const r=await fetch('http://127.0.0.1:'+port+route,{headers:{Authorization:'Bearer '+key},redirect:'error',signal:AbortSignal.timeout(2000)});assert(r.ok);return nativeReviewJSON(r);}
let activityTimer,activityPending,activityStopped=false,activityState;
function acceptActivity(value){const next=nativeReviewActivity(value,activityState?.instance,activityState?.sequence??0);activityState=next;receipt.source_instance=next.instance;const r=receipt.request_phase_observations??={samples:0,preparing_max:0,active_max:0,responding_max:0,uncertainty_observed:false,observer_included:true,authority:false};r.samples++;for(const phase of ['preparing','active','responding'])r[phase+'_max']=Math.max(r[phase+'_max'],next[phase]);r.uncertainty_observed ||= next.uncertain;}
let componentSequence=0;
async function sampleComponents(){
 if(!capsule.receipt.declared_inputs.source_component_diagnostics)return;
 const value=nativeReviewComponents(await get('/v1/fios/source-components'),activityState.instance,componentSequence);componentSequence=value.sequence;
 assert(value.available&&value.stream.enabled&&value.host.enabled&&value.metal.enabled,'Private source components unavailable');
 const record=receipt.source_component_observations??={samples:0,coherent_samples:0,uncertainty_observed:false,shared_stream_observed:false,stream_registered_max:0,creation_pending_max:0,host_pending_max:0,host_active_max:0,metal_pending_max:0,metal_captures_max:0,authority:false,coverage:'unknown'};
 record.samples++;if(value.coherent)record.coherent_samples++;
 if(value.uncertainty_site>0){record.uncertainty_observed=true;record.first_uncertainty_site??=value.uncertainty_site;assert.equal(record.first_uncertainty_site,value.uncertainty_site);record.sdk_patch_sha256=capsule.receipt.declared_inputs.mlx_source_dependency.patch_sha256;}
 record.uncertainty_observed ||= value.stream.uncertain||value.host.uncertain||value.metal.uncertain;record.shared_stream_observed ||= value.stream.shared;
 for(const [key,n]of Object.entries({stream_registered_max:value.stream.registered,creation_pending_max:value.stream.pending,host_pending_max:value.host.pending,host_active_max:value.host.active,metal_pending_max:value.metal.pending,metal_captures_max:value.metal.captures}))record[key]=Math.max(record[key],n);
}
let lineageSequence=0;
async function readLineage(correlation){
 const controlPath=path.join(home,'.fios-native-control/control.sock'),parent=lstatSync(path.dirname(controlPath)),socketInfo=lstatSync(controlPath);
 assert(parent.isDirectory()&&!parent.isSymbolicLink()&&parent.uid===process.getuid()&&(parent.mode&0o077)===0&&socketInfo.isSocket()&&socketInfo.uid===process.getuid()&&(socketInfo.mode&0o777)===0o600);
 const frame=Buffer.alloc(64);frame.write('FIQ9');frame[4]=1;Buffer.from(activityState.instance,'hex').copy(frame,8);Buffer.from(correlation,'hex').copy(frame,24);
 const bytes=await new Promise((ok,no)=>{
  const socket=createConnection({path:controlPath});let output=Buffer.alloc(0),settled=false,timer;
  const finish=error=>{if(settled)return;settled=true;clearTimeout(timer);socket.destroy();error?no(error):ok(output);};
  timer=setTimeout(()=>finish(new Error('Lineage deadline')),500);socket.once('error',finish);
  socket.on('data',chunk=>{output=Buffer.concat([output,chunk]);if(output.length>112)finish(new Error('Lineage limit'));});
  socket.once('end',()=>finish());socket.once('connect',()=>socket.end(frame));
 });
 const value=nativeReviewLineage(bytes,activityState.instance,correlation,lineageSequence);lineageSequence=value.sequence;return value;
}
async function sampleLineages(){
 if(!pair||receipt.requests?.length!==2)return;
 const [a,b]=receipt.requests;
 const first=await readLineage(a.correlation),second=await readLineage(b.correlation),again=await readLineage(a.correlation);
 const proof=receipt.correlated_lineage_observations??={samples:0,retained_overlap_samples:0,authority:false,scope:'retained_request_lineages_not_gpu_concurrency_or_terminality'};
 proof.samples++;
 if([first,second,again].every(v=>v.found&&!v.uncertain)&&first.root_sequence===again.root_sequence){
  const roots=[first.root_sequence,second.root_sequence];if(proof.roots)assert.deepEqual(proof.roots,roots,'Native roots changed for a one-shot request');else proof.roots=roots;
  proof.retained_overlap_samples++;
  proof.distinct_roots=first.root_sequence!==second.root_sequence;
  assert(proof.distinct_roots,'Distinct requests aliased a native root');
 }
}
function sampleActivity(){if(activityStopped||activityPending)return;activityPending=(async()=>{acceptActivity(await get('/v1/fios/activity'));await Promise.all([sampleLineages(),sampleComponents()]);})().catch(()=>{failed='request_phase_or_lineage_observation_failed';modelAbort.abort();}).finally(()=>{activityPending=null;});}
async function requestModel(index){
 const request={index,correlation:randomBytes(32).toString('hex'),dispatched_ms:Math.round(performance.now()-began),response_complete:false};
 (receipt.requests??=[]).push(request);receipt.model_post_attempts++;assert(receipt.model_post_attempts<=LIMITS.model_posts);receipt.actual_model_posts=null;save();
 const response=await fetch('http://127.0.0.1:'+port+'/v1/chat/completions',{method:'POST',redirect:'error',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','X-Fios-Request-ID':request.correlation},body:JSON.stringify({model:ID,messages:[{role:'user',content:image?[{type:'text',text:'What is the dominant color? Reply with one word.'},{type:'image_url',image_url:{url:'data:image/png;base64,'+readFileSync(path.join(root,'tests/fixtures/platform/native-image-64.png')).toString('base64')}}]:'Reply with one word: ready.'}],max_tokens:LIMITS.output_tokens,temperature:0,stream:true,stream_options:{include_usage:true}}),signal:AbortSignal.any([AbortSignal.timeout(LIMITS.request_ms),modelAbort.signal])});
 request.http_status=response.status;receipt.actual_model_posts=receipt.requests.every(r=>r.http_status!==undefined)?receipt.model_post_attempts:null;save();
 if(!response.ok){let value;try{value=await nativeReviewJSON(response,16384);}catch{}request.http_failure=nativeReviewHTTPFailure(response.status,value);receipt.http_failure??=request.http_failure;if(image&&request.http_failure.modality_error==='vision_unavailable')failed='selected_model_vision_unavailable';throw Error('Native model request refused');}
 let buffer='',bytes=0,done=false,deltas=0,completionTokens=null;const decoder=new TextDecoder('utf-8',{fatal:true});
 for await(const chunk of response.body){bytes+=chunk.length;assert(bytes<=65536&&!failed);buffer+=decoder.decode(chunk,{stream:true});let at;while((at=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,at).trim();buffer=buffer.slice(at+1);if(!line.startsWith('data:'))continue;const data=line.slice(5).trim();if(data==='[DONE]'){done=true;continue;}const value=JSON.parse(data);assert(!value.error);if(value.choices?.some(c=>['content','reasoning_content'].some(k=>typeof c.delta?.[k]==='string'&&c.delta[k].length>0)))deltas++;if(value.usage?.completion_tokens!==undefined){assert(Number.isSafeInteger(value.usage.completion_tokens)&&value.usage.completion_tokens>=0&&value.usage.completion_tokens<=LIMITS.output_tokens);completionTokens=value.usage.completion_tokens;}}}
 assert(decoder.decode()===''&&done&&completionTokens!==null&&completionTokens>0);
 Object.assign(request,{completion_tokens:completionTokens,delta_events:deltas,response_complete:true,completed_ms:Math.round(performance.now()-began)});save();return request;
}

try{
 const identityDeadline=performance.now()+2000;while(!original&&performance.now()<identityDeadline&&!ended()){try{original=observe();}catch{await delay(20);}}assert(original,'Owned process identity unavailable');receipt.original_process={pid:original.pid,uid:original.uid,start:original.start};receipt.peak_resident=original.resident;receipt.peak_footprint=original.footprint;if(Math.max(original.resident,original.footprint)>LIMITS.memory_abort_bytes){failed='memory_abort_threshold';modelAbort.abort();signalOwned('SIGKILL');throw Error('Resource threshold');}save();stage='resource_monitor';
 timer=setInterval(()=>{if(ended())return;try{const p=observe();assert(p.start===original.start);receipt.peak_resident=Math.max(receipt.peak_resident,p.resident);receipt.peak_footprint=Math.max(receipt.peak_footprint,p.footprint);if(Math.max(p.resident,p.footprint)>LIMITS.memory_abort_bytes){failed='memory_abort_threshold';modelAbort.abort();signalOwned('SIGKILL');}}catch{failed='resource_identity_unknown';modelAbort.abort();signalOwned('SIGTERM');}if(performance.now()-began>LIMITS.work_ms){failed='overall_deadline';modelAbort.abort();signalOwned('SIGKILL');}},500);
 stage='readiness';let ready=false;for(let i=0;i<200&&!ready;i++){assert(!ended()&&!failed);try{ready=(await get('/health')).status==='ok';}catch{await delay(25);}}assert(ready,'Private source readiness unavailable');
 stage='catalog';const before=await get('/v1/models');assert(Array.isArray(before.data));assert(before.data.every(m=>!m.loaded&&m.state!=='ready'),'Unexpected preloaded model');
 stage='diagnostic';acceptActivity(await get('/v1/fios/activity'));await sampleComponents();
 if(check){assert(before.data.length===0);receipt.result='empty_model_profile_and_identity_passed';}
 else{
  assert(before.data.some(m=>m.id===ID),'Exact selected model not advertised');receipt.native_uncertainty=true;receipt.native_inference=null;receipt.inference_attempted=true;save();
  activityTimer=setInterval(sampleActivity,100);stage='model_requests';
  const pending=Array.from({length:LIMITS.model_posts},(_,index)=>requestModel(index));let results;
  try{results=await Promise.all(pending);}catch(error){modelAbort.abort();await Promise.allSettled(pending);throw error;}
  assert(receipt.model_post_attempts===LIMITS.model_posts&&receipt.actual_model_posts===LIMITS.model_posts);postsDone=true;receipt.native_inference=true;
  clearInterval(activityTimer);activityStopped=true;if(activityPending)await activityPending;acceptActivity(await get('/v1/fios/activity'));await sampleComponents();
  assert(receipt.request_phase_observations.preparing_max>0||receipt.request_phase_observations.active_max>0||receipt.request_phase_observations.responding_max>0,'No live model request phase observed');
  if(pair){
   assert(Math.max(...results.map(r=>r.dispatched_ms))<Math.min(...results.map(r=>r.completed_ms)),'Client requests did not overlap');
   assert(receipt.correlated_lineage_observations?.retained_overlap_samples>0,'No bracketed retained lineage overlap observed');
   receipt.result='overlapping_same_model_responses_complete';
  }else{
   receipt.completion_tokens=results[0].completion_tokens;receipt.delta_events=results[0].delta_events;receipt.result=image?'single_source_image_response_complete':'single_source_model_response_complete';
  }
  receipt.generated_text_logged=false;
 }
 assert(!failed);receipt.elapsed_ms=Math.round(performance.now()-began);
}catch{receipt.result='failed';receipt.reason=failed||'review_'+stage+'_failure';process.exitCode=1;}
finally{
 clearInterval(timer);clearInterval(activityTimer);modelAbort.abort();activityStopped=true;const cleanupStarted=performance.now();signalOwned('SIGTERM');if(activityPending)await activityPending;let end=cleanupStarted+5000;while(!ended()&&performance.now()<end)await delay(25);if(!ended()){signalOwned('SIGKILL');end=performance.now()+2000;while(!ended()&&performance.now()<end)await delay(25);}
 receipt.process_reaped=ended();if(!receipt.process_reaped){receipt.result='failed';receipt.reason='owned_process_not_reaped';process.exitCode=1;child.unref();child.stdout.destroy();child.stderr.destroy();}
 receipt.response_complete=postsDone;save();console.log(JSON.stringify({...receipt,directory}));
}
