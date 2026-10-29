#!/usr/bin/env node
// --isolated: actual manager/task IPC plus one512MiB/1CPU runner. --mock:
// real manager refusal paths without Docker. Synthetic
// resource observations, no model binding/worker/inference or installed policy.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,writeFileSync,readFileSync,readdirSync,realpathSync,chmodSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {createConnection} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
const mock=process.argv[2]==='--mock';assert.deepEqual(process.argv.slice(2),[mock?'--mock':'--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-manager-'),children=[];
const docker=join(directory,'docker'),binary=join(directory,'manager-fixture'),owner=randomUUID();
let socketURL,image,sentinel,sentinelName,passed=false;
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
 const child=spawn(binary,[state,docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,mode],{cwd:root,env:environment,stdio:'ignore'});children.push(child);
 await until(async()=>{assert(!exited(child),'Fixture manager exited');try{return (await rpc(state,'status',{},'observe')).ok;}catch(error){if(['ENOENT','ECONNREFUSED'].includes(error.code))return false;throw error;}});
 return child;
}
async function stop(child){if(!exited(child))child.kill('SIGTERM');await until(()=>exited(child),5000);assert.equal(child.exitCode,0,'Fixture manager failed graceful exit');}
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
 command('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),main,'-o',binary],180000,{...process.env});
 const source=Buffer.from("print('MANAGER_LOOP_FIXTURE')\n"),token=randomBytes(32).toString('base64');
 function begin(){return {owner:token,phase:'begin',idempotency:randomUUID(),kind:'sandbox',length:source.length,sha256:createHash('sha256').update(source).digest('hex'),lifetime:30000,model:null,image,memory:536870912,cpus:1};}
 for(const [mode,error]of [['disabled','native_unsupported'],['closed','native_unsupported'],['missing','resource_limit']]) {
  const state=join(directory,mode),child=await start(state,mode);
  const response=await rpc(state,'job.create',begin());assert.equal(response.ok,false);assert.equal(response.error,error);
  const status=await rpc(state,'status',{},'observe');assert.equal(status.native_activity,'unsupported');assert.equal(status.worker_reservations,0);assert.equal(status.unresolved_requests,0);
  await stop(child);
 }
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
  if(ids&&!owned.length){const value=JSON.parse(runtime(['inspect','--type=container',ids]));assert.equal(value.length,1);const item=value[0];assert.equal(item.Id,ids);assert.equal(item.Name,'/fios-sandbox-'+job);assert.equal(item.Image,image);assert.equal(item.Config.Labels['fios.platform.job'],job);assert.match(item.Config.Labels['fios.platform.nonce'],/^[a-f0-9]{64}$/);owned.push({id:ids,name:item.Name,image,nonce:item.Config.Labels['fios.platform.nonce'],job});}
  if(response.result.state==='removed'&&typeof response.result.code_complete==='boolean'&&typeof response.result.exit_verified==='boolean'){done=response.result;return true;}return false;
 },60000);
 assert(owned.length===1,'Actual container identity was not observed');assert(text.includes('MANAGER_LOOP_FIXTURE'));assert.equal(done.code_complete,true);assert.equal(done.exit_verified,true);assert.equal(done.unresolved_managed_requests,0);
 assert.equal(runtime(['ps','-a','--no-trunc','--filter','id='+owned[0].id,'--format','{{.ID}}']),'');
 await stop(child);child=await start(state,'closed');await delay(2200);
 const restored=await rpc(state,'job.status',{job,owner:token});assert.equal(restored.ok,true);assert.equal(restored.result.state,'removed');assert.equal(runtime(['ps','-a','--no-trunc','--filter','name=^/fios-sandbox-'+job+'$','--format','{{.ID}}']),'');await stop(child);
 const preserved=JSON.parse(runtime(['inspect','--type=container',sentinel]))[0];assert.equal(preserved.Id,sentinel);assert.equal(preserved.Name,'/'+sentinelName);assert.equal(preserved.Image,image);assert.equal(preserved.Config.Labels['lab.fios.fixture.owner'],owner);
 runtime(['rm',sentinel]);sentinel=undefined;
 const imageState=JSON.parse(runtime(['image','inspect',image]))[0];assert.equal(imageState.Config.Labels['lab.fios.fixture.owner'],owner);runtime(['image','rm',image]);image=undefined;
 passed=true;
 console.log('PASS: actual manager task IPC→bounded upload→isolated runner→owner output→verified removal; duplicate end/restart do not replay; foreign owner/default/closed/missing-source refuse; unrelated sentinel preserved.');
 console.log('SYNTHETIC host/VM sources only;512MiB/1CPU immutable fixture, no model binding/worker/inference, installed enrollment or native acceptance.');
 }
} finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 try{await until(()=>children.every(exited),5000);}catch{for(const child of children)if(!exited(child))child.kill('SIGKILL');await until(()=>children.every(exited),2000);}
 if(passed)rmSync(directory,{recursive:true,force:true});
 else {writeFileSync(join(directory,'fixture-receipt.json'),JSON.stringify({image,sentinel,owned,jobs},null,2)+'\n',{mode:0o600});console.error('RETAINED: '+directory+'; runtime objects/state preserved for diagnosis, no global cleanup.');}
}
