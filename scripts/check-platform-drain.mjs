#!/usr/bin/env node
// Real disposable manager IPC, synthetic cache/never-dispatched ledger. No
// native app/CLI, model, Docker daemon, privileged action or installed state.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,copyFileSync,readdirSync,readFileSync,writeFileSync,existsSync,rmSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createConnection} from 'node:net';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {DatabaseSync} from 'node:sqlite';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-drain-'),children=[];
const source=join(directory,'ServiceDrainLive.swift'),binary=join(directory,'drain-fixture'),core=join(root,'platform/studio/Sources/StudioCore');
const profile=join(directory,'network.sb');
writeFileSync(profile,'(version 1)\n(allow default)\n(deny network*)\n(allow network* (local unix-socket) (remote unix-socket))\n',{mode:0o600});
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ServiceDrainLive.swift.fixture'),source);
const build=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),source,'-o',binary],{cwd:root,stdio:'inherit',timeout:180000});
assert.equal(build.status,0,'Drain fixture build failed');
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=10000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Finite drain fixture deadline');}
function rpc(state,operation,payload={},lane='control'){
 return new Promise((accept,reject)=>{
  const socket=createConnection({path:join(state,lane+'.sock')});let bytes=Buffer.alloc(0);
  socket.setTimeout(2000,()=>socket.destroy(Error('Drain fixture RPC deadline')));socket.once('error',reject);
  socket.on('data',part=>{bytes=Buffer.concat([bytes,part]);if(bytes.length>65540)socket.destroy(Error('Drain fixture response overflow'));});
  socket.once('end',()=>{try{assert(bytes.length>=4);assert.equal(bytes.readUInt32BE(),bytes.length-4);accept(JSON.parse(bytes.subarray(4)));}catch(error){reject(error);}});
  socket.once('connect',()=>{const body=Buffer.from(JSON.stringify({version:1,id:randomUUID(),operation,payload})),header=Buffer.alloc(4);header.writeUInt32BE(body.length);socket.end(Buffer.concat([header,body]));});
 });
}
let passed=false;
try{
 for(const mode of ['closed','configured','held']){
  const state=join(directory,mode),child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,mode],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:['pipe','ignore','pipe']});children.push(child);
  let failed=false;child.stderr.on('data',()=>{failed=true;});
  await until(async()=>{assert(!failed&&!exited(child),'Drain manager startup failed');try{return (await rpc(state,'status',{},'observe')).ok;}catch(error){if(['ENOENT','ECONNREFUSED'].includes(error.code))return false;throw error;}});
  const first=await rpc(state,'status',{},'observe'),ids=JSON.parse(readFileSync(join(directory,mode+'-jobs.json'),'utf8'));
  assert.equal(first.unresolved_requests,2);assert.equal(first.worker_reservations,2);
  for(const lane of ['observe','task']){const result=await rpc(state,'service.drain',{service:'mlx'},lane);assert.equal(result.ok,false);assert.equal(result.error,'unauthorized');}
  const missing=await rpc(state,'service.drain',{service:'mlx'});assert.equal(missing.ok,false);assert.equal(missing.error,'native_unsupported');
  if(mode!=='closed'){
   child.stdin.write(JSON.stringify({epoch:first.epoch,mode:'original'})+'\n');
   await until(()=>existsSync(join(directory,mode+'-cache-ready')));
   const result=await rpc(state,'service.drain',{service:'mlx'});
   if(mode==='held'){assert.equal(result.ok,false);assert.equal(result.error,'native_unsupported');}
   else{
    assert.equal(result.ok,true);assert.equal(result.maintenance_applied,true);assert.equal(result.native_action_applied,false);assert.equal(result.drain.revocations_requested,1);assert.equal(result.drain.state,'draining');
    const status=await rpc(state,'status',{},'observe');assert.equal(status.services.mlx.desired,'maintenance');assert.equal(status.unresolved_requests,2);assert.equal(status.worker_reservations,2);
    const force=await rpc(state,'service.force',{service:'mlx',phase:'prepare'});assert.equal(force.ok,false);assert.equal(force.error,'native_unsupported');assert.equal(force.applied,false);
    child.stdin.write(JSON.stringify({epoch:first.epoch,mode:'omit'})+'\n');
    await until(()=>readFileSync(join(directory,mode+'-cache-ready'),'utf8')==='omit');
    await until(async()=>{const value=await rpc(state,'status',{},'observe');return value.services.mlx.drain?.state==='refused'&&value.services.mlx.drain.reason==='activity_unknown';});
    const resume=await rpc(state,'service.desired',{service:'mlx',desired:'running'});assert.equal(resume.ok,true);assert.equal(resume.applied,false);
    assert.equal((await rpc(state,'status',{},'observe')).services.mlx.drain,undefined,'Superseded drain report survived newer operator intent');
   }
  }
  child.stdin.end();child.kill('SIGTERM');await until(()=>exited(child),5000);assert.equal(child.exitCode,0);assert(!failed);
  // Only after confirmed manager exit: no simultaneous SQLite app instance.
  const db=new DatabaseSync(join(state,'state.sqlite'),{readOnly:true});
  try{const rows=db.prepare('SELECT id,payload FROM jobs').all().map(row=>({id:row.id,state:JSON.parse(row.payload).state}));assert.equal(rows.find(row=>row.id===ids.owned).state,mode==='configured'?'revoking':'reconciling');assert.equal(rows.find(row=>row.id===ids.other).state,'reconciling');assert.equal(db.prepare('SELECT count(*) AS n FROM inference WHERE uncertain=1').get().n,2);}finally{db.close();}
 }
 passed=true;console.log('PASS: actual manager drain IPC, closed/held/task/observer refusal, maintenance-before-owned revoke, hidden-uncertainty fence, superseding intent and force still disabled; no native/model/runtime action');
}finally{
 for(const child of children)if(!exited(child))child.kill('SIGKILL');
 await Promise.all(children.map(async child=>{if(!exited(child))await until(()=>exited(child),3000);}));
 if(passed&&children.every(exited))rmSync(directory,{recursive:true});else console.error('Drain fixture failed; retained private state for diagnosis.');
}
