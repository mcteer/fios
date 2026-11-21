#!/usr/bin/env node
// Normal held/overlapping HTTP streams against an owned mock provider. No models.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,readdirSync} from 'node:fs';
import {createHash,randomBytes} from 'node:crypto';
import {createServer,request as httpRequest} from 'node:http';
import {createServer as netServer} from 'node:net';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
import {nativeReviewJSON,nativeReviewActivity} from './lib/platform-native-review-intent.mjs';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
const capsule=verifyNativeReview(args[2],args[4]);
assert.equal(capsule.receipt.declared_inputs.provider_source_fixture,true);
assert.equal(capsule.receipt.declared_inputs.model_effects,'forbidden');
const directory=mkdtempSync('/private/tmp/f9-http-stream-'),sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const core=path.join(root,'platform/studio/Sources/StudioCore'),swift=path.join(root,'platform/studio/Tests/StudioCoreTests/NativeHTTPLineage.swift.fixture');
const coreFiles=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>path.join(core,n));
const observerSource=path.join(root,'platform/studio/Tests/NativeFixtures/ObserveProcess.c.fixture');
const inputs=Object.fromEntries([process.argv[1],swift,observerSource,...coreFiles].map(p=>[p,sha(p)]));
function build(program,argv,name){const r=spawnSync(program,argv,{encoding:'utf8',timeout:180000,maxBuffer:2<<20});writeFileSync(path.join(directory,name+'.log'),(r.stdout??'')+(r.stderr??''));assert.equal(r.status,0,'Fixture compile failed; retain '+directory);}
const observer=path.join(directory,'observe'),reader=path.join(directory,'lineage'),main=path.join(directory,'Main.swift');
writeFileSync(main,readFileSync(swift));
build('/usr/bin/clang',['-x','c',observerSource,'-O2','-o',observer],'observer-build');
build('/usr/bin/swiftc',['-swift-version','6','-warnings-as-errors','-O','-I',path.join(root,'platform/studio/Sources/CSQLite'),...coreFiles,main,'-o',reader],'lineage-build');
const pending=[],clients=[],samples=[];let posts=0,child,original,launchError=false,logBytes=0,peak=0,instance;
const first='data: '+JSON.stringify({choices:[{index:0,delta:{content:'one'}}]})+'\n\n';
const last='data: '+JSON.stringify({choices:[{index:0,delta:{content:'two'},finish_reason:'stop'}]})+'\n\ndata: [DONE]\n\n';
const provider=createServer((request,response)=>{
 if(request.method!=='POST'){const body=JSON.stringify({data:[{id:'fixture-probe',object:'model'}]});response.writeHead(200,{'Content-Type':'application/json'});response.end(body);return;}
 let bytes=0;request.on('data',part=>{bytes+=part.length;if(bytes>16384)request.destroy();});
 request.on('end',()=>{posts++;if(posts>2){response.writeHead(503);response.end();return;}response.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache'});response.write(first);pending.push(response);});
});
await new Promise((ok,no)=>{provider.once('error',no);provider.listen(0,'127.0.0.1',ok);});
const providerPort=provider.address().port,reserve=netServer();await new Promise((ok,no)=>{reserve.once('error',no);reserve.listen(0,'127.0.0.1',ok);});
const port=reserve.address().port;await new Promise(ok=>reserve.close(ok));
const home=path.join(directory,'h'),models=path.join(home,'empty-models');mkdirSync(home,{mode:0o700});mkdirSync(models,{mode:0o700});mkdirSync(path.join(home,'.mlx-serve'),{mode:0o700});
writeFileSync(path.join(home,'.mlx-serve/providers.json'),JSON.stringify([{name:'fixture',url:'http://127.0.0.1:'+providerPort+'/v1',models:['fixture-probe']}]),{mode:0o600});
const key=randomBytes(32).toString('hex'),deadline=performance.now()+45000;
const ended=()=>!child||(launchError&&!child.pid)||child.exitCode!==null||child.signalCode!==null;
function identity(){const r=spawnSync(observer,[String(child.pid)],{encoding:'utf8',timeout:1000,maxBuffer:2048});assert.equal(r.status,0);const value=JSON.parse(r.stdout);assert.equal(value.pid,child.pid);assert.equal(value.uid,process.getuid());if(original)assert.equal(value.start,original.start);else original=value;return value;}
function observe(){assert(!ended());const value=identity();peak=Math.max(peak,value.resident,value.footprint);assert(peak<=2**30);assert(logBytes<=128*1024);assert(performance.now()<deadline);}
function signal(value){if(ended()||!original)return;try{identity();child.kill(value);}catch{}}
async function stop(){if(ended())return;signal('SIGTERM');const end=performance.now()+3000;while(!ended()&&performance.now()<end-1000)await delay(10);if(!ended())signal('SIGKILL');while(!ended()&&performance.now()<end)await delay(10);assert(ended(),'Own source process not reaped; retain state');}
async function get(route){observe();const response=await fetch('http://127.0.0.1:'+port+route,{headers:{Authorization:'Bearer '+key},redirect:'error',signal:AbortSignal.timeout(1500)});return {status:response.status,value:await nativeReviewJSON(response,16384)};}
function lineage(id){observe();const r=spawnSync(reader,[capsule.binary,String(child.pid),path.join(home,'.fios-native-control/control.sock'),instance,id],{encoding:'utf8',timeout:3000,maxBuffer:8192});assert.equal(r.status,0,'Native lineage read failed; retain '+directory);const value=JSON.parse(r.stdout);samples.push(value);observe();return value;}
async function waitFor(fn){while(performance.now()<deadline){observe();const value=fn();if(value)return value;await delay(20);}throw Error('Normal stream deadline');}
async function openStream(id){
 return new Promise((ok,no)=>{
  const body=JSON.stringify({model:'fixture-probe@fixture',messages:[{role:'user',content:'fixture'}],max_tokens:2,stream:true});
  const request=httpRequest('http://127.0.0.1:'+port+'/v1/chat/completions',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','Content-Length':Buffer.byteLength(body),'X-Fios-Request-ID':id}},response=>{
   clients.push(response);
   if(response.statusCode!==200){response.destroy();no(new Error('Unexpected mock stream status: '+response.statusCode));return;}
   let bytes=0;const parts=[];
   const done=new Promise((resolve,reject)=>{response.on('data',part=>{bytes+=part.length;if(bytes>65536){response.destroy(new Error('Mock stream exceeded its byte limit'));return;}parts.push(part);});response.once('end',()=>resolve(Buffer.concat(parts)));response.once('error',reject);});
   done.catch(()=>{});response.pause();ok({response,done});
  });
  request.setTimeout(15000,()=>request.destroy(new Error('Normal stream timeout')));request.once('error',no);request.end(body);
 });
}
function checkBody(bytes){const events=bytes.toString('utf8').split('\n').filter(s=>s.startsWith('data: ')).map(s=>s.slice(6));assert(events.includes('[DONE]'));const content=events.filter(s=>s!=='[DONE]').map(s=>JSON.parse(s).choices?.[0]?.delta?.content??'').join('');assert.equal(content,'onetwo');return createHash('sha256').update(bytes).digest('hex');}
try{
 const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:home,XDG_CACHE_HOME:path.join(home,'cache'),LANG:'C',LC_ALL:'C',FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_PROXY_KEY:key};
 child=spawn('/usr/bin/sandbox-exec',['-D','FIOS_REVIEW_ENDPOINT=localhost:'+port,'-D','FIOS_REVIEW_PROVIDER=localhost:'+providerPort,'-D','FIOS_REVIEW_STATE='+home,'-D','FIOS_REVIEW_BINARY='+capsule.binary,'-f',path.join(root,'tests/fixtures/platform/native-proxy-review.sb'),capsule.binary,'serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--api-key-env','FIOS_SOURCE_PROXY_KEY','--api-key-strict'],{cwd:home,env,stdio:['ignore','pipe','pipe']});
 child.once('error',()=>{launchError=true;});for(const pipe of [child.stdout,child.stderr])pipe.on('data',part=>{logBytes+=part.length;});
 let healthy=false;while(!healthy){observe();try{healthy=(await get('/health')).status===200;}catch{await delay(25);}}
 instance=nativeReviewActivity((await get('/v1/fios/activity')).value).instance;
 const idA=randomBytes(32).toString('hex'),idB=randomBytes(32).toString('hex');
 const a=await openStream(idA);await waitFor(()=>pending.length===1);
 const heldA=await waitFor(()=>{const value=lineage(idA);return value.found&&value.owners>0?value:null;});
 const b=await openStream(idB);await waitFor(()=>pending.length===2);
 const heldB=await waitFor(()=>{const value=lineage(idB);return value.found&&value.owners>0?value:null;});
 assert.notEqual(heldA.root,heldB.root);assert.equal(lineage(idA).root,heldA.root);
 pending[0].end(last);a.response.resume();const bodyA=checkBody(await a.done);
 await waitFor(()=>!lineage(idA).found);
 const remaining=lineage(idB);assert(remaining.found&&remaining.owners>0);assert.equal(remaining.root,heldB.root);
 pending[1].end(last);b.response.resume();const bodyB=checkBody(await b.done);
 await waitFor(()=>!lineage(idB).found);assert.equal(posts,2);
 assert(Object.entries(inputs).every(([p,digest])=>sha(p)===digest));
 const result={scope:'normal_owned_provider_HTTP_stream_and_overlap_lineage',capsule_sha256:args[4],inputs,samples,mock_provider_posts:posts,real_model_posts:0,model_weight_loads:0,body_sha256:[bodyA,bodyB],response_reader_paused:true,upstream_response_held:true,independent_original_roots:true,first_finish_preserves_second:true,OS_backpressure_acceptance:false,installed:false,native_authority:false,peak_process_bytes:peak};
 const receipt=path.join(directory,'receipt.json');writeFileSync(receipt,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify({ok:true,directory,receipt_sha256:sha(receipt),mock_provider_posts:posts,real_model_posts:0}));
}finally{for(const response of clients)response.destroy();for(const response of pending)response.destroy();try{await stop();}finally{provider.closeAllConnections();await new Promise(ok=>provider.close(ok));}}
