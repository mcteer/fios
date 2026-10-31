#!/usr/bin/env node
// --isolated: actual manager/task IPC plus one512MiB/1CPU runner. --mock:
// real manager refusal paths without Docker. Synthetic
// resource observations. --models uses installed workers with a fake endpoint
// only; no real inference, installed policy or native acceptance.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,writeFileSync,readFileSync,readdirSync,realpathSync,chmodSync,rmSync,existsSync,unlinkSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {createConnection} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
const mock=process.argv[2]==='--mock',models=process.argv[3]==='--models',mutateHold=process.argv[3]==='--mutate-hold';assert.deepEqual(process.argv.slice(2),[mock?'--mock':'--isolated',...(models?['--models']:mutateHold?['--mutate-hold']:[])]);assert(!mutateHold||mock,'Hold mutation is Docker-free only');assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-manager-'),children=[];
const docker=join(directory,'docker'),binary=join(directory,'manager-fixture'),owner=randomUUID();
let socketURL,image,sentinel,sentinelName,passed=false;
const python=join(root,'.venv/bin/python');
const owned=[],jobs=[];
const environment={PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty',DOCKER_CONFIG:'/var/empty',DOCKER_BUILDKIT:'0'};
const exited=child=>child.exitCode!==null||child.signalCode!==null;
function command(file,args,timeout=120000,env=environment){
 const result=spawnSync(file,args,{encoding:'utf8',timeout,maxBuffer:1<<20,env});
 assert.equal(result.status,0,`Finite fixture command failed: ${file} (${result.status??result.signal})`);return result.stdout.trim();
}
const runtime=args=>command(docker,['--host',socketURL,...args]);
async function until(check,timeout=30000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(100);}throw Error('Finite manager execution deadline');}
function rpc(state,operation,payload={},lane='task'){
 return new Promise((accept,reject)=>{
  const socket=createConnection({path:join(state,lane+'.sock')});let output=Buffer.alloc(0);
  socket.setTimeout(3000,()=>socket.destroy(Error('Finite fixture RPC deadline')));socket.once('error',reject);
  socket.on('data',bytes=>{output=Buffer.concat([output,bytes]);if(output.length>65540)socket.destroy(Error('Fixture response overflow'));});
  socket.once('end',()=>{try{assert(output.length>=4);assert.equal(output.readUInt32BE(),output.length-4);accept(JSON.parse(output.subarray(4)));}catch(error){reject(error);}});
  socket.once('connect',()=>{const data=Buffer.from(JSON.stringify({version:1,id:randomUUID(),operation,payload})),header=Buffer.alloc(4);header.writeUInt32BE(data.length);socket.end(Buffer.concat([header,data]));});
 });
}
async function start(state,mode){
 mkdirSync(state,{recursive:true,mode:0o700});
 const child=spawn(binary,[state,docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,mode,...(mode==='models'?[join(root,'.venv/bin/python')]:[])],{cwd:root,env:environment,stdio:mode==='models'?['pipe','ignore','ignore']:'ignore'});children.push(child);
 await until(async()=>{assert(!exited(child),'Fixture manager exited');try{return (await rpc(state,'status',{},'observe')).ok;}catch(error){if(['ENOENT','ECONNREFUSED'].includes(error.code))return false;throw error;}});
 return child;
}
async function stop(child){if(!exited(child))child.kill('SIGTERM');await until(()=>exited(child),5000);assert.equal(child.exitCode,0,'Fixture manager failed graceful exit');}
async function nativeMock(epoch) {
 const path=join(directory,'native');mkdirSync(path,{recursive:true,mode:0o700});
 const child=spawn(python,['-I','-B',join(root,'tests/fixtures/platform/native-server.py'),path,epoch],{cwd:root,env:environment,stdio:['pipe','pipe','pipe']});children.push(child);
 const value={child,path,port:null,posts:0};let buffer='',failure;
 child.stdout.on('data',chunk=>{try{buffer+=chunk;assert(buffer.length<4096);while(buffer.includes('\n')){const index=buffer.indexOf('\n'),event=JSON.parse(buffer.slice(0,index));buffer=buffer.slice(index+1);if(Object.keys(event).join()==='port'){assert(event.port>=49152&&event.port<=65535);value.port=event.port;}else{assert.deepEqual(Object.keys(event),['posts']);assert.equal(event.posts,value.posts+1);value.posts=event.posts;}}}catch(error){failure=error;}});
 child.stderr.on('data',()=>{failure=Error('Native mock fixture failed');});
 await until(()=>{if(failure)throw failure;assert(!exited(child));return value.port;},5000);
 return value;
}
async function stopMock(value){value.child.stdin.end();await until(()=>exited(value.child),3000);assert.equal(value.child.exitCode,0);}
async function modelCase(stale) {
 const state=join(directory,stale?'models-stale':'models'),ready=join(directory,'model-cache-ready');if(existsSync(ready))unlinkSync(ready);
 const child=await start(state,'models'),status=await rpc(state,'status',{},'observe');
 const native=await nativeMock(status.epoch),token=randomBytes(32).toString('base64');
 child.stdin.end(JSON.stringify({base:`http://127.0.0.1:${native.port}/v1`,path:join(native.path,'observe.sock'),epoch:stale?randomUUID():status.epoch}));
 await until(()=>existsSync(ready));
 function begin(data,kind='model'){return {owner:token,phase:'begin',idempotency:randomUUID(),kind,length:data.length,sha256:createHash('sha256').update(data).digest('hex'),lifetime:30000,model:'fixture/model',image:kind==='model'?null:image,memory:kind==='model'?0:536870912,cpus:kind==='model'?0:1};}
 const context=Buffer.from(JSON.stringify([{role:'user',content:'fixture only'}]));
 if(stale){const response=await rpc(state,'job.create',begin(context));assert.equal(response.ok,false);assert.equal(response.error,'model_unavailable');assert.equal(native.posts,0);const observed=await rpc(state,'status',{},'observe');assert.equal(observed.worker_reservations,0);assert.equal(observed.unresolved_requests,0);await stop(child);await stopMock(native);return;}
 async function upload(data,kind) {
  const created=await rpc(state,'job.create',begin(data,kind));assert.equal(created.ok,true,created.error);const job=created.result.job;jobs.push(job);
  for(const fields of [{phase:'chunk',job,index:0,data:data.toString('base64')},{phase:'end',job}]){const result=await rpc(state,'job.create',{owner:token,...fields});assert.equal(result.ok,true,result.error);}return job;
 }
 const unavailable=await rpc(state,'job.create',{...begin(context),model:'fixture/missing'});assert.equal(unavailable.ok,false);assert.equal(unavailable.error,'model_unavailable');assert.equal(native.posts,0,'Unavailable model triggered substitution');
 const job=await upload(context,'model');let answer='',terminal;
 await until(async()=>{const response=await rpc(state,'job.status',{job,owner:token});assert.equal(response.ok,true,response.error);const event=response.result.event;if(event?.type==='model.text')answer+=event.content;if(event?.type==='model.done')terminal=event.status;return response.result.state==='removed'&&terminal!==undefined;});
 assert.equal(answer,'MOCK_ONLY');assert.equal(terminal,'complete');assert.equal(native.posts,1);
 const replay=await rpc(state,'job.create',{owner:token,phase:'end',job});assert.equal(replay.ok,true);await delay(300);assert.equal(native.posts,1,'Consumed input replayed a model POST');
 if(!mock) {
  const source=readFileSync(join(root,'tests/fixtures/platform/sandbox-task.py')),sandbox=await upload(source,'sandbox');let text='',done;
  await until(async()=>{const response=await rpc(state,'job.status',{job:sandbox,owner:token});assert.equal(response.ok,true,response.error);const event=response.result.event;if(event?.type==='output')text+=Buffer.from(event.data,'base64').toString();
   const ids=runtime(['ps','-a','--no-trunc','--filter','name=^/fios-sandbox-'+sandbox+'$','--format','{{.ID}}']);if(ids&&!owned.some(x=>x.job===sandbox)){const item=JSON.parse(runtime(['inspect','--type=container',ids]))[0];assert.equal(item.Id,ids);assert.equal(item.Name,'/fios-sandbox-'+sandbox);assert.equal(item.Image,image);assert.equal(item.Config.Labels['fios.platform.job'],sandbox);assert.match(item.Config.Labels['fios.platform.nonce'],/^[a-f0-9]{64}$/);owned.push({id:ids,name:item.Name,image,job:sandbox,nonce:item.Config.Labels['fios.platform.nonce']});}
   if(response.result.state==='removed'&&typeof response.result.exit_verified==='boolean'){done=response.result;return true;}return false;
  },60000);
  assert(text.includes('SANDBOX_TASK_PASS'));assert.equal(done.code_complete,true);assert.equal(done.exit_verified,true);assert.equal(done.unresolved_managed_requests,0);assert.equal(native.posts,2);
  const saved=owned.find(x=>x.job===sandbox);assert(saved);assert.equal(runtime(['ps','-a','--no-trunc','--filter','id='+saved.id,'--format','{{.ID}}']),'');
 }
 await until(async()=>{const value=await rpc(state,'status',{},'observe');return value.worker_reservations===0&&value.unresolved_requests===0;});
 assert.equal((await rpc(state,'status',{},'observe')).services.mlx.desired,'running','Model/frame-looking output gained management authority');
 await stop(child);await stopMock(native);
 console.log('PASS: actual manager model-only'+(mock?'':' and sandbox-mediated')+' IPC uses installed no-tools worker, exact fake POST counts, completion/reap and replay refusal; stale source epoch sends zero requests.');
}
try {
 if(mock) {
  copyFileSync('/usr/bin/false',docker);chmodSync(docker,0o700);
  socketURL='unix:///fixture/never.sock';image='sha256:'+'a'.repeat(64);
 } else {
 const located=spawnSync('/usr/bin/which',['docker'],{encoding:'utf8',timeout:3000});assert.equal(located.status,0);
 copyFileSync(realpathSync(located.stdout.trim()),docker);chmodSync(docker,0o700);
 socketURL=command(docker,['context','inspect','--format','{{.Endpoints.docker.Host}}'],10000,process.env);
 assert(socketURL.startsWith('unix:///'),'Only local private runtime allowed');
 assert.equal(realpathSync(socketURL.slice(7)),realpathSync(join(homedir(),'.orbstack/run/docker.sock')),'Only the existing local OrbStack endpoint is permitted');
 const base=runtime(['image','inspect','fios:current','--format','{{.Id}}']);assert.match(base,/^sha256:[a-f0-9]{64}$/);
 copyFileSync(join(root,'platform/studio/sandbox/runner.py'),join(directory,'runner.py'));
 writeFileSync(join(directory,'Dockerfile'),`FROM ${base}\nLABEL lab.fios.fixture.owner="${owner}"\nUSER 65532:65532\nWORKDIR /workspace\nCOPY runner.py /runner.py\nENTRYPOINT ["/opt/venv/bin/python","-I","-B","/runner.py"]\n`);
 image=runtime(['build','--quiet','--pull=false','--network=none',directory]);assert.match(image,/^sha256:[a-f0-9]{64}$/);
 sentinelName='fios-manager-sentinel-'+owner;
 sentinel=runtime(['create','--name',sentinelName,'--pull=never','--network=none','--read-only','--user=65532:65532','--cap-drop=ALL','--security-opt=no-new-privileges:true','--memory=67108864','--memory-swap=67108864','--cpus=1','--pids-limit=16','--log-driver=none','--label','lab.fios.fixture.owner='+owner,image]);assert.match(sentinel,/^[a-f0-9]{64}$/);
 }
 const main=join(directory,'ManagerExecutionLive.swift'),core=join(root,'platform/studio/Sources/StudioCore');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ManagerExecutionLive.swift.fixture'),main);
 command('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>{
  if(!mutateHold||name!=='Manager.swift')return join(core,name);
  const value=readFileSync(join(core,name),'utf8'),check='let activeExecution=migrationHeld ? nil:execution';
  assert.equal(value.split(check).length,2,'Migration hold boundary changed');
  const path=join(directory,'MutatedManager.swift');writeFileSync(path,value.replace(check,'let activeExecution=execution'));return path;
 }),main,'-o',binary],180000,{...process.env});
 const source=Buffer.from("print('MANAGER_LOOP_FIXTURE')\n"),token=randomBytes(32).toString('base64');
 function begin(){return {owner:token,phase:'begin',idempotency:randomUUID(),kind:'sandbox',length:source.length,sha256:createHash('sha256').update(source).digest('hex'),lifetime:30000,model:null,image,memory:536870912,cpus:1};}
 for(const [mode,error]of [['disabled','native_unsupported'],['held','native_unsupported'],['closed','native_unsupported'],['missing','resource_limit']]) {
  const state=join(directory,mode),child=await start(state,mode);
  if(mode==='held'){const status=await rpc(state,'status',{},'observe');assert.equal(status.migration_maintenance,true);assert.equal(status.sandbox_admission,'disabled','Migration maintenance hold accepted execution ports');}
  const response=await rpc(state,'job.create',begin());assert.equal(response.ok,false);assert.equal(response.error,error);
  const status=await rpc(state,'status',{},'observe');assert.equal(status.native_activity,'unsupported');assert.equal(status.worker_reservations,0);assert.equal(status.unresolved_requests,0);
  await stop(child);
 }
 if(models){await modelCase(true);await modelCase(false);}
 if(mock) {
  passed=true;
  console.log('PASS: real disposable manager IPC refuses default/closed/missing-source execution with zero workers/native requests; harmless stand-in only, no daemon calls.');
 } else {
 const state=join(directory,'configured');let child=await start(state,'configured');
 const created=await rpc(state,'job.create',begin());assert.equal(created.ok,true,created.error);const job=created.result.job;assert.match(job,/^[a-f0-9-]{36}$/);jobs.push(job);
 const foreign=await rpc(state,'job.status',{job,owner:randomBytes(32).toString('base64')});assert.equal(foreign.error,'unauthorized');
 for(const payload of [{phase:'chunk',job,index:0,data:source.toString('base64')},{phase:'end',job},{phase:'end',job}]) {const response=await rpc(state,'job.create',{owner:token,...payload});assert.equal(response.ok,true,response.error);}
 let text='',done;
 await until(async()=>{
  const response=await rpc(state,'job.status',{job,owner:token});assert.equal(response.ok,true,response.error);
  const event=response.result.event;if(event?.data)text+=Buffer.from(event.data,'base64').toString();
  const ids=runtime(['ps','-a','--no-trunc','--filter','name=^/fios-sandbox-'+job+'$','--format','{{.ID}}']);
  if(ids&&!owned.some(item=>item.job===job)){const value=JSON.parse(runtime(['inspect','--type=container',ids]));assert.equal(value.length,1);const item=value[0];assert.equal(item.Id,ids);assert.equal(item.Name,'/fios-sandbox-'+job);assert.equal(item.Image,image);assert.equal(item.Config.Labels['fios.platform.job'],job);assert.match(item.Config.Labels['fios.platform.nonce'],/^[a-f0-9]{64}$/);owned.push({id:ids,name:item.Name,image,nonce:item.Config.Labels['fios.platform.nonce'],job});}
  if(response.result.state==='removed'&&typeof response.result.code_complete==='boolean'&&typeof response.result.exit_verified==='boolean'){done=response.result;return true;}return false;
 },60000);
 assert(owned.filter(item=>item.job===job).length===1,'Actual container identity was not observed');assert(text.includes('MANAGER_LOOP_FIXTURE'));assert.equal(done.code_complete,true);assert.equal(done.exit_verified,true);assert.equal(done.unresolved_managed_requests,0);
 assert.equal(runtime(['ps','-a','--no-trunc','--filter','id='+owned.find(item=>item.job===job).id,'--format','{{.ID}}']),'');
 await stop(child);child=await start(state,'closed');await delay(2200);
 const restored=await rpc(state,'job.status',{job,owner:token});assert.equal(restored.ok,true);assert.equal(restored.result.state,'removed');assert.equal(runtime(['ps','-a','--no-trunc','--filter','name=^/fios-sandbox-'+job+'$','--format','{{.ID}}']),'');await stop(child);
 const preserved=JSON.parse(runtime(['inspect','--type=container',sentinel]))[0];assert.equal(preserved.Id,sentinel);assert.equal(preserved.Name,'/'+sentinelName);assert.equal(preserved.Image,image);assert.equal(preserved.Config.Labels['lab.fios.fixture.owner'],owner);
 runtime(['rm',sentinel]);sentinel=undefined;
 const imageState=JSON.parse(runtime(['image','inspect',image]))[0];assert.equal(imageState.Config.Labels['lab.fios.fixture.owner'],owner);runtime(['image','rm',image]);image=undefined;
 passed=true;
 console.log('PASS: actual manager task IPC→bounded upload→isolated runner→owner output→verified removal; duplicate end/restart do not replay; foreign owner/default/closed/missing-source refuse; unrelated sentinel preserved.');
 console.log('SYNTHETIC host/VM sources only;512MiB/1CPU immutable fixture, '+(models?'installed worker with fake endpoint only':'no model binding/worker')+', no real inference, installed enrollment or native acceptance.');
 }
} finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 try{await until(()=>children.every(exited),5000);}catch{for(const child of children)if(!exited(child))child.kill('SIGKILL');await until(()=>children.every(exited),2000);}
 if(passed)rmSync(directory,{recursive:true,force:true});
 else {writeFileSync(join(directory,'fixture-receipt.json'),JSON.stringify({image,sentinel,owned,jobs},null,2)+'\n',{mode:0o600});console.error('RETAINED: '+directory+'; runtime objects/state preserved for diagnosis, no global cleanup.');}
}
