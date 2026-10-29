#!/usr/bin/env node
// Actual source-built native HTTP, EMPTY model directory only. No inference,
// model loading, installed server/restart, LAN discovery, distributed mode,
// provider proxy, credentials or production state.
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, realpathSync, lstatSync, readdirSync, copyFileSync, existsSync } from 'node:fs';
import { createServer, createConnection } from 'node:net';
import { request } from 'node:http';
import { join, isAbsolute } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
const args=process.argv.slice(2);
assert(args.length===5 && args[0]==='--isolated' && args[1]==='--binary' && args[3]==='--sha256' && isAbsolute(args[2]) && /^[a-f0-9]{64}$/.test(args[4]),
  'usage: check-platform-native-http.mjs --isolated --binary ABS_SOURCE_FIXTURE --sha256 REVIEWED_SHA256');
assert.notEqual(process.getuid(),0);
const binary=realpathSync(args[2]);
assert(binary.startsWith('/private/tmp/') || binary.startsWith('/tmp/'), 'only a disposable source fixture can be selected');
assert(lstatSync(binary).isFile());
assert.equal(createHash('sha256').update(readFileSync(binary)).digest('hex'),args[4]);
const scratch=mkdtempSync('/tmp/f9-native-http-'),models=join(scratch,'empty-models');
mkdirSync(models,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:scratch,LANG:'C',LC_ALL:'C',XDG_CACHE_HOME:join(scratch,'cache'),FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture'};
let child,manager,plainChild,partialHeader,partialBody;
async function exit(milliseconds,owned=child) {
  const deadline=Date.now()+milliseconds;
  while(owned.exitCode===null && owned.signalCode===null && Date.now()<deadline) await delay(25);
  return owned.exitCode!==null || owned.signalCode!==null;
}
try {
  const version=spawnSync(binary,['--version'],{env,encoding:'utf8',timeout:5000,maxBuffer:8192});
  assert.equal(version.status,0,'source fixture version failed');
  assert((version.stdout+version.stderr).includes('26.10.3-fios-source-fixture'),'not the source fixture binary');
  const reservation=createServer();
  await new Promise((resolve,reject)=>{reservation.once('error',reject);reservation.listen(0,'127.0.0.1',resolve);});
  const port=reservation.address().port;
  await new Promise(resolve=>reservation.close(resolve));
  // No --lan-share/--lan-discover or --dist flags: both are explicitly opt-in
  // in the pinned source. MAS build disables provider subprocess support.
  child=spawn(binary,['serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager'],{env,stdio:['ignore','ignore','pipe']});
  let diagnosticBytes=0;
  child.stderr.on('data',chunk=>{diagnosticBytes+=chunk.length;if(diagnosticBytes>128*1024)child.kill('SIGTERM');});
  async function get(path='/v1/fios/activity',headers={}) {
    return new Promise((resolve,reject)=>{
      const req=request({host:'127.0.0.1',port,path,method:'GET',headers,agent:false,timeout:2000},res=>{
        let bytes=Buffer.alloc(0);
        res.on('data',chunk=>{bytes=Buffer.concat([bytes,chunk]);if(bytes.length>65536){res.destroy();reject(new Error('oversize native diagnostic'));}});
        res.once('error',reject);
        res.once('end',()=>resolve({status:res.statusCode,body:JSON.parse(bytes.toString('utf8'))}));
      });
      req.once('timeout',()=>req.destroy(new Error('native fixture HTTP deadline')));
      req.once('error',reject);req.end();
    });
  }
  async function until(test,milliseconds=5000) {
    const deadline=Date.now()+milliseconds;
    while(Date.now()<deadline) {
      assert.equal(child.exitCode,null,'source fixture exited before acceptance');
      assert.equal(child.signalCode,null,'source fixture was signalled before acceptance');
      try {const value=await test();if(value)return value;}catch(error){if(!['ECONNREFUSED','ENOENT'].includes(error.code))throw error;}
      await delay(25);
    }
    throw new Error('native source fixture acceptance deadline');
  }
  const controlPath=join(scratch,'.fios-native-control/control.sock');
  function frame(op,instance='0'.repeat(32),sequence=0n) {
    const value=Buffer.alloc(32);value.write('FIC9');value[4]=2;value[5]=op;
    value.writeBigUInt64BE(sequence,8);Buffer.from(instance,'hex').copy(value,16);return value;
  }
  async function controlRaw(bytes) {
    return new Promise((resolve,reject)=>{
      const socket=createConnection({path:controlPath});let output=Buffer.alloc(0);
      socket.setTimeout(3500,()=>socket.destroy(new Error('private control deadline')));
      socket.once('error',reject);socket.on('data',chunk=>{output=Buffer.concat([output,chunk]);if(output.length>64)socket.destroy(new Error('private control oversize'));});
      socket.once('end',()=>resolve(output));socket.once('connect',()=>socket.end(bytes));
    });
  }
  async function control(op,instance,sequence) {
    const bytes=await controlRaw(frame(op,instance,sequence));assert.equal(bytes.length,64);
    assert.equal(bytes.subarray(0,4).toString(),'FIR9');assert.equal(bytes[4],2);assert.equal(bytes[5],op);
    assert.equal(bytes[7],0);assert.equal(bytes[59],0);assert(bytes[58]<=6);assert(bytes.readUInt32BE(60)<=256);
    const value={status:bytes[6],instance:bytes.subarray(8,24).toString('hex'),sequence:bytes.readBigUInt64BE(24),
      owned:bytes.readUInt32BE(32),ingress:bytes.readUInt32BE(36),preparing:bytes.readUInt32BE(40),active:bytes.readUInt32BE(44),responding:bytes.readUInt32BE(48),closed:bytes[56],uncertain:bytes[57],ownerOutcome:bytes[58],streams:bytes.readUInt32BE(60)};
    assert.equal(value.owned,value.ingress+value.preparing+value.active+value.responding);return value;
  }
  let sourceInstance;
  function diagnostic(value) {
    assert.equal(value.status,200);assert.equal(value.body.coverage,'unknown');
    assert.equal(value.body.reason,'native_ownership_audit_incomplete');assert.equal(value.body.observer_included,true);
    assert.equal(value.body.uncertain,false);
    assert.equal(value.body.admissions_closed,false,'source fixture started with an unexpected native admission gate');
    assert.match(value.body.source_instance,/^[a-f0-9]{32}$/);
    assert.notEqual(value.body.source_instance,'0'.repeat(32));
    sourceInstance??=value.body.source_instance;
    assert.equal(value.body.source_instance,sourceInstance,'native source instance changed within one process');
    assert.equal(value.body.owned_requests,value.body.ingress+value.body.preparing+value.body.active+value.body.responding);
    assert.equal(value.body.preparing,0);assert.equal(value.body.active,0);
    assert(value.body.owned_requests>=1 && value.body.owned_requests<=256);
    return value.body;
  }
  const initial=await until(async()=>{const value=diagnostic(await get());return value.owned_requests===1 && value;});
  assert.deepEqual((await get('/v1/models')).body.data,[],'empty source fixture discovered a model');
  // A different port and no control flag isolate the early startup lock from
  // ordinary HTTP-port/control-socket collision refusal later in startup.
  const duplicateEnv={...env};delete duplicateEnv.FIOS_NATIVE_CONTROL;
  const duplicate=spawnSync(binary,['serve','--host','127.0.0.1','--port','0','--model-dir',models,'--no-warmup-eager'],{env:duplicateEnv,encoding:'utf8',timeout:3000,maxBuffer:16384});
  assert.equal(duplicate.signal,null,'duplicate fixture blocked instead of refusing');
  assert.notEqual(duplicate.status,0,'duplicate fixture was allowed');
  assert.match(duplicate.stderr,/StartupGuardUnavailable/,'duplicate refusal did not originate from the startup guard');
  assert(!duplicate.stderr.includes('Metal GPU:'),'duplicate reached native initialization');
  assert.equal((await get()).body.source_instance,sourceInstance,'duplicate changed the original serving instance');
  console.log('PASS: opted-in duplicate native fixture refused before native initialization on a separate port, without control-socket conflict; original process remains responsive.');

  assert.equal(lstatSync(join(scratch,'.fios-native-control')).mode&0o777,0o700);
  assert.equal(lstatSync(controlPath).mode&0o777,0o600);assert.equal(lstatSync(controlPath).uid,process.getuid());
  const controlInitial=await control(0);assert.equal(controlInitial.instance,sourceInstance);assert.equal(controlInitial.closed,0);
  const root=fileURLToPath(new URL('../',import.meta.url)),core=join(root,'platform/studio/Sources/StudioCore');
  const swiftMain=join(scratch,'NativeControlLive.swift'),swiftClient=join(scratch,'native-control-client');
  copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/NativeControlLive.swift.fixture'),swiftMain);
  const compiled=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),
    ...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),swiftMain,'-o',swiftClient],{encoding:'utf8',timeout:120000,maxBuffer:2<<20});
  assert.equal(compiled.status,0,'native Swift control fixture compilation failed: '+compiled.stderr);
  function swiftControl(op,instance='-',sequence='0',hash=args[4]) {
    return spawnSync(swiftClient,['--isolated',controlPath,binary,hash,String(child.pid),String(op),instance,String(sequence)],
      {encoding:'utf8',timeout:5000,maxBuffer:8192});
  }
  const swiftObserved=swiftControl(0);assert.equal(swiftObserved.status,0,'Swift native peer authentication failed');
  assert.equal(JSON.parse(swiftObserved.stdout).instance,sourceInstance);
  assert.notEqual(swiftControl(1,sourceInstance,'0','0'.repeat(64)).status,0,'wrong native artifact hash authorized pause');
  assert.equal((await control(0)).closed,0,'failed native authentication changed admission');
  assert.equal((await control(3,sourceInstance,1n)).status,1,'owner-stream probe ran with admissions open');
  const swiftPaused=swiftControl(1,sourceInstance);assert.equal(swiftPaused.status,0);
  const swiftTicket=JSON.parse(swiftPaused.stdout);assert.equal(swiftTicket.closed,true);assert.equal(swiftTicket.activity,'unknown');
  await assert.rejects(get(),error=>['ECONNRESET','EPIPE'].includes(error.code));
  const ownerProbe=await control(3,sourceInstance,BigInt(swiftTicket.sequence));
  assert.equal(ownerProbe.status,0);assert.equal(ownerProbe.ownerOutcome,1,'native owner CPU/GPU default streams were not explicitly enrolled/synchronized');
  assert.equal(ownerProbe.streams,2,'empty native fixture did not synchronize both owned CPU/GPU defaults');
  console.log(`SOURCE FIXTURE ONLY: partial native MLX owner-stream outcome=${ownerProbe.ownerOutcome}, synchronized_streams=${ownerProbe.streams}; global activity remains unknown.`);
  const swiftProbe=swiftControl(3,sourceInstance,swiftTicket.sequence);assert.equal(swiftProbe.status,0);
  assert.equal(JSON.parse(swiftProbe.stdout).activity,'unknown','partial owner-stream barrier became global idle');
  const swiftResumed=swiftControl(2,sourceInstance,swiftTicket.sequence);assert.equal(swiftResumed.status,0);
  assert.equal(JSON.parse(swiftResumed.stdout).closed,false);diagnostic(await get());
  assert.equal((await control(1,'f'.repeat(32))).status,3,'foreign source instance changed ingress');
  assert.equal((await control(4)).status,1,'unknown management opcode accepted');
  assert.equal((await controlRaw(Buffer.concat([frame(1,sourceInstance),frame(1,sourceInstance)]))).length,0,'trailing control frame executed');
  diagnostic(await get());
  async function partial(bytes) {
    const socket=createConnection({host:'127.0.0.1',port});
    socket.on('error',()=>{});
    await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('error',reject);});
    socket.write(bytes);return socket;
  }
  partialHeader=await partial('POST /v1/chat/completions HTTP/1.1\r\nHost:');
  partialBody=await partial('POST /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\n{');
  const busy=await until(async()=>{const value=diagnostic(await get());return value.owned_requests>=3 && value.ingress>=3 && value;});
  assert(busy.sequence>initial.sequence,'native source allocation sequence did not advance');
  const tunneled=await get('/v1/fios/activity',{'X-MLX-LAN':'1'});
  assert.equal(tunneled.status,403,'local tunnel-marked observation bypassed local-only policy');
  const plain=diagnostic(await get('/v1/fios/activity?role=operator&command=service.force'));
  assert.equal(plain.coverage,'unknown','query parameters changed source authority');
  const paused=await control(1,sourceInstance);assert.equal(paused.status,0);assert.equal(paused.closed,1);assert(paused.owned>=2);
  assert.equal((await control(3,sourceInstance,paused.sequence)).ownerOutcome,2,'owner-stream probe bypassed live ingress');
  await assert.rejects(get(),error=>['ECONNRESET','EPIPE'].includes(error.code),'new native ingress crossed private maintenance fence');
  partialHeader.destroy();partialHeader=undefined;partialBody.destroy();partialBody=undefined;
  await until(async()=>{const value=await control(0);return value.closed===1 && value.owned===0;});
  assert.equal((await control(2,sourceInstance,paused.sequence)).status,0);
  await until(async()=>diagnostic(await get()).owned_requests===1);
  assert.deepEqual((await get('/v1/models')).body.data,[],'source fixture performed model discovery/loading');
  const again=await control(1,sourceInstance);assert(again.sequence>paused.sequence);
  const replay=await control(2,sourceInstance,paused.sequence);assert.equal(replay.status,1);assert.equal(replay.closed,1);assert.equal(replay.uncertain,1);
  assert.equal((await control(2,sourceInstance,again.sequence)).status,0);
  const final=await get();assert.equal(final.body.coverage,'unknown');assert.equal(final.body.uncertain,true,'resume cleared native uncertainty');
  const managerState=join(scratch,'manager-state');mkdirSync(managerState,{mode:0o700});
  function startManager() {
    manager=spawn(swiftClient,['--isolated-manager',managerState,controlPath,binary,args[4],'source-fixture-only',String(child.pid)],{env,stdio:['ignore','ignore','pipe']});
    let bytes=0;manager.stderr.on('data',chunk=>{bytes+=chunk.length;if(bytes>65536)manager.kill('SIGTERM');});
  }
  async function stopManager() {
    if(!manager || manager.exitCode!==null || manager.signalCode!==null)return;
    const owned=manager;owned.kill('SIGTERM');
    let deadline=Date.now()+5000;
    while(owned.exitCode===null && owned.signalCode===null && Date.now()<deadline)await delay(25);
    if(owned.exitCode===null && owned.signalCode===null){owned.kill('SIGKILL');deadline=Date.now()+2000;while(owned.exitCode===null && owned.signalCode===null && Date.now()<deadline)await delay(25);}
    assert(owned.exitCode!==null || owned.signalCode!==null,'source manager fixture was not reaped');
  }
  async function managerRPC(operation,payload={},role='control') {
    return new Promise((resolve,reject)=>{
      const id=randomUUID(),body=Buffer.from(JSON.stringify({version:1,id,operation,payload})),header=Buffer.alloc(4);header.writeUInt32BE(body.length);
      const socket=createConnection({path:join(managerState,role+'.sock')});let output=Buffer.alloc(0);
      socket.setTimeout(5000,()=>socket.destroy(new Error('manager private RPC deadline')));
      socket.once('error',reject);socket.once('connect',()=>socket.write(Buffer.concat([header,body])));
      socket.on('data',chunk=>{
        output=Buffer.concat([output,chunk]);if(output.length>65540){socket.destroy();reject(new Error('manager response oversize'));return;}
        if(output.length>=4 && output.length===4+output.readUInt32BE(0)){socket.destroy();const value=JSON.parse(output.subarray(4).toString());if(value.ok)assert.equal(value.id,id);resolve(value);}
      });
    });
  }
  startManager();
  await until(async()=>{const status=await managerRPC('status');return status.ok && status;});
  const denied=await managerRPC('service.desired',{service:'mlx',desired:'maintenance'},'task');assert.equal(denied.ok,false);
  const requested=await managerRPC('service.desired',{service:'mlx',desired:'maintenance'});assert.equal(requested.ok,true);assert.equal(requested.applied,false);
  await until(async()=>{const status=await managerRPC('status');assert.equal(status.native_activity,'unsupported');return status.native_admissions==='admissionsClosed' && status.services.mlx.desired==='maintenance';});
  assert.equal((await control(0)).closed,1);
  await stopManager();startManager();
  await until(async()=>{const status=await managerRPC('status');return status.native_admissions==='admissionsClosed' && status.services.mlx.desired==='maintenance';});
  assert.equal((await control(0)).closed,1,'manager restart silently reopened native admissions');
  assert.equal((await managerRPC('service.desired',{service:'mlx',desired:'running'})).applied,false);
  await until(async()=>{const status=await managerRPC('status');return status.native_admissions==='admissionsOpen';});
  assert.equal((await control(0)).closed,0);assert.equal((await get()).body.coverage,'unknown');
  await stopManager();
  const plainHome=join(scratch,'without-control');mkdirSync(plainHome,{mode:0o700});
  const plainModels=join(plainHome,'empty-models');mkdirSync(plainModels,{mode:0o700});
  const plainReservation=createServer();await new Promise((resolve,reject)=>{plainReservation.once('error',reject);plainReservation.listen(0,'127.0.0.1',resolve);});
  const plainPort=plainReservation.address().port;await new Promise(resolve=>plainReservation.close(resolve));
  const plainEnv={...env,HOME:plainHome,XDG_CACHE_HOME:join(plainHome,'cache')};delete plainEnv.FIOS_NATIVE_CONTROL;delete plainEnv.FIOS_NATIVE_STARTUP;
  plainChild=spawn(binary,['serve','--host','127.0.0.1','--port',String(plainPort),'--model-dir',plainModels,'--no-warmup-eager'],{env:plainEnv,stdio:['ignore','ignore','ignore']});
  const unconfigured=await until(()=>new Promise((resolve,reject)=>{
    const req=request({host:'127.0.0.1',port:plainPort,path:'/v1/fios/activity',agent:false,timeout:2000},res=>{
      let bytes=Buffer.alloc(0);res.on('data',chunk=>{bytes=Buffer.concat([bytes,chunk]);if(bytes.length>65536)res.destroy();});
      res.once('error',reject);res.once('end',()=>{try{resolve(JSON.parse(bytes.toString()));}catch(error){reject(error);}});
    });req.once('error',reject);req.once('timeout',()=>req.destroy(new Error('default source fixture deadline')));req.end();
  }));
  assert.equal(unconfigured.coverage,'unknown');assert.equal(unconfigured.admissions_closed,false);assert.notEqual(unconfigured.source_instance,sourceInstance);
  assert.equal(existsSync(join(plainHome,'.fios-native-control')),false,'ordinary startup created a management endpoint without explicit source opt-in');
  assert.equal(existsSync(join(plainHome,'.fios-native-startup')),false,'ordinary startup created fixture lock state');
  plainChild.kill('SIGTERM');if(!await exit(5000,plainChild)){plainChild.kill('SIGKILL');assert(await exit(2000,plainChild));}
  console.log('PASS: no private control directory/socket without explicit fixture opt-in; independent process instance identity.');
  console.log('PASS: manager role refusal, durable maintenance before asynchronous native pause, restart reconciliation without reopening/replay, explicit resume and unchanged unsupported lifecycle/activity.');
  console.log('PASS: private Unix control permissions/source binding, finite/trailing frame refusal, pause with existing ingress, continued private observation, closed new ingress, drain/resume and old-ticket replay fencing. No quiescence authority.');
  console.log('PASS: actual ReleaseFast source fixture HTTP; pre-header/pre-body ingress ownership, observer inclusion, bounded unknown-only diagnostic, tunnel refusal, inert query data and ownership release after connection close.');
  console.log('EMPTY MODELS ONLY: no model POST was completed, no inference/model load/native installed service or release enrollment is established.');
} finally {
  partialHeader?.destroy();partialBody?.destroy();
  if(manager && manager.exitCode===null && manager.signalCode===null) {
    const owned=manager;owned.kill('SIGTERM');const deadline=Date.now()+5000;
    while(owned.exitCode===null && owned.signalCode===null && Date.now()<deadline)await delay(25);
    if(owned.exitCode===null && owned.signalCode===null){owned.kill('SIGKILL');await new Promise(resolve=>owned.once('exit',resolve));}
  }
  if(plainChild && plainChild.exitCode===null && plainChild.signalCode===null) {
    assert.equal(existsSync(join(plainHome,'.fios-native-startup')),false,'ordinary startup created fixture lock state');
  plainChild.kill('SIGTERM');if(!await exit(5000,plainChild)){plainChild.kill('SIGKILL');assert(await exit(2000,plainChild));}
  }
  if(child && child.exitCode===null && child.signalCode===null) {
    child.kill('SIGTERM');if(!await exit(5000)){child.kill('SIGKILL');assert(await exit(2000),'owned source fixture could not be reaped');}
  }
  rmSync(scratch,{recursive:true,force:true});
}
