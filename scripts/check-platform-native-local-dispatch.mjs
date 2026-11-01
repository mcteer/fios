#!/usr/bin/env node
// Process-bound requests must not become provider/peer execution. No models.
import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
import {createServer as httpServer} from 'node:http';
import {createServer} from 'node:net';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewJSON,nativeReviewActivity} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
const capsule=verifyNativeReview(args[2],args[4]),directory=mkdtempSync('/private/tmp/f9-local-dispatch-');
assert.equal(capsule.receipt.declared_inputs.provider_source_fixture,true,'Positive proxy control requires a model-free provider source capsule');
const observer=path.join(directory,'observe');
execFileSync('/usr/bin/clang',['-x','c',path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture'),'-O2','-o',observer],{timeout:30000,stdio:'pipe'});
let forwarded=0,child,original,launchError=false,size=0,peak=0;
const provider=httpServer((request,response)=>{
 const end=request.method==='POST' ? {error:{type:'fixture_no_inference'}}:{data:[{id:'fixture-probe',object:'model'}]};
 let bytes=0;request.on('data',part=>{bytes+=part.length;if(bytes>16384)request.destroy();});
 request.on('end',()=>{if(request.method==='POST')forwarded++;const body=JSON.stringify(end);response.writeHead(request.method==='POST'?503:200,{'Content-Type':'application/json','Content-Length':Buffer.byteLength(body)});response.end(body);});
});
await new Promise((ok,no)=>{provider.once('error',no);provider.listen(0,'127.0.0.1',ok);});
const providerPort=provider.address().port;
const reserve=createServer();await new Promise((ok,no)=>{reserve.once('error',no);reserve.listen(0,'127.0.0.1',ok);});
const port=reserve.address().port;await new Promise(ok=>reserve.close(ok));
const home=path.join(directory,'home'),models=path.join(home,'empty-models');mkdirSync(home,{mode:0o700});mkdirSync(models,{mode:0o700});
const config=path.join(home,'.mlx-serve');mkdirSync(config,{mode:0o700});
writeFileSync(path.join(config,'providers.json'),JSON.stringify([{name:'fixture',url:'http://127.0.0.1:'+providerPort+'/v1',models:['fixture-probe']}]),{mode:0o600});
const key=randomBytes(32).toString('hex'),started=performance.now(),deadline=started+20000;
const ended=()=>!child||(launchError&&!child.pid)||child.exitCode!==null||child.signalCode!==null;
function identity(){
 const result=spawnSync(observer,[String(child.pid)],{encoding:'utf8',timeout:1000,maxBuffer:2048});assert.equal(result.status,0);
 const value=JSON.parse(result.stdout);assert(value.pid===child.pid&&value.uid===process.getuid());
 if(original)assert.equal(value.start,original.start);else original=value;return value;
}
function signal(value){if(ended()||!original)return;try{identity();child.kill(value);}catch{}}
async function stop(){
 if(ended())return;const until=performance.now()+3000;signal('SIGTERM');
 while(!ended()&&performance.now()<until-1000)await delay(10);
 if(!ended())signal('SIGKILL');while(!ended()&&performance.now()<until)await delay(10);
 if(!ended()){child.unref();child.stdout.destroy();child.stderr.destroy();throw Error('Own source process not reaped; preserve uncertainty and state');}
}
async function request(route,{instance,post=false,model='fixture-probe@fixture'}={}){
 const response=await fetch('http://127.0.0.1:'+port+route,{method:post?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(1500),headers:{Authorization:'Bearer '+key,...(instance?{'X-Fios-Native-Instance':instance}:{}),...(post?{'Content-Type':'application/json'}:{})},...(post?{body:JSON.stringify({model,messages:[],max_tokens:1})}:{})});
 return {status:response.status,value:await nativeReviewJSON(response,16384)};
}
try{
 const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:home,XDG_CACHE_HOME:path.join(home,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_PROXY_KEY:key};
 child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_PROVIDER=localhost:'+providerPort,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',path.join(root,'tests/fixtures/platform/native-proxy-review.sb'),capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--api-key-env','FIOS_SOURCE_PROXY_KEY','--api-key-strict'],{cwd:home,env,stdio:['ignore','pipe','pipe']});
 child.once('error',()=>{launchError=true;});for(const pipe of [child.stdout,child.stderr])pipe.on('data',part=>{size+=part.length;if(size>128*1024)signal('SIGTERM');});
 let healthy=false;while(performance.now()<deadline-5000&&!healthy){
  assert(!ended());const value=identity();peak=Math.max(peak,value.resident,value.footprint);assert(peak<=256*2**20);
  try{healthy=(await request('/health')).status===200;}catch{await delay(25);}
 }
 assert(healthy,'Empty source startup deadline');
 const instance=nativeReviewActivity((await request('/v1/fios/activity')).value).instance;
 const baseline=forwarded,bound=await request('/v1/chat/completions',{instance,post:true});
 const boundForwards=forwarded-baseline;
 const legacy=await request('/v1/chat/completions',{post:true}),legacyForwards=forwarded-baseline-boundForwards;
 const missing=await request('/v1/chat/completions',{instance,post:true,model:'unregistered-local-fixture'});
 const defaults=[];for(const model of ['', 'mlx-serve']){const result=await request('/v1/chat/completions',{instance,post:true,model});defaults.push({model,status:result.status,type:result.value.error?.type});}
 writeFileSync(path.join(directory,'observations.json'),JSON.stringify({bound_status:bound.status,bound_type:bound.value.error?.type,bound_provider_posts:boundForwards,legacy_status:legacy.status,legacy_type:legacy.value.error?.type,legacy_provider_posts:legacyForwards,missing_status:missing.status,missing_type:missing.value.error?.type,defaults})+'\n',{mode:0o600});
 assert.equal(legacy.status,503);assert.equal(legacy.value.error?.type,'fixture_no_inference');assert.equal(legacyForwards,1,'Positive proxy control must reach the owned metadata-only provider');
 assert.equal(bound.status,409,'A process-bound target must refuse before provider dispatch');assert.equal(bound.value.error?.type,'native_target_not_local');assert.equal(boundForwards,0);
 assert.equal(missing.status,404);assert.equal(missing.value.error?.type,'native_target_not_found');
 for(const result of defaults){assert.equal(result.status,404);assert.equal(result.type,'native_target_not_found');}
 assert.equal(forwarded-baseline,1);assert(performance.now()<deadline);await stop();
 const result={ok:true,source_fixture_only:true,capsule_sha256:args[4],bound_status:bound.status,bound_provider_posts:boundForwards,legacy_provider_posts:legacyForwards,missing_local_status:missing.status,default_target_refusals:defaults.length,model_loads:0,native_inference:false,installed_service_actions:0,native_authority:false,observed_process_bytes:peak,elapsed_ms:Math.round(performance.now()-started),directory};
 writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(result)+'\n',{mode:0o600});console.log(JSON.stringify(result));
}finally{await stop();provider.closeAllConnections();await new Promise(ok=>provider.close(ok));}
