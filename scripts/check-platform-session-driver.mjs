#!/usr/bin/env node
// Real coordinator/Unix/kernel identities, trusted counter-only fake app ports.
// Never calls the production enrolled factory or NSWorkspace application API.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,readdirSync,readFileSync,existsSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const mutation=process.argv[3]==='--mutate-expiry';
assert.deepEqual(process.argv.slice(2),mutation?['--isolated','--mutate-expiry']:['--isolated']);
const root=fileURLToPath(new URL('../',import.meta.url)),temporary=mkdtempSync('/tmp/fios009-session-driver-'),children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=5000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(20);}throw Error('Finite session driver fixture deadline');}
const policy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
try {
 const fixture=join(temporary,'DriverFixture.swift'),binary=join(temporary,'driver-fixture'),core=join(root,'platform/studio/Sources/StudioCore');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SessionDriver.swift.fixture'),fixture);
 const sources=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>{
  const original=join(core,n);if(!mutation||n!=='EnrolledSessionDriver.swift')return original;
  const source=readFileSync(original,'utf8'),edge='systemUptime>=check.deadline';assert.equal(source.split(edge).length,2);
  const copy=join(temporary,n);writeFileSync(copy,source.replace(edge,edge+'+60'));return copy;
 });
 const built=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,fixture,'-o',binary],{cwd:root,encoding:'utf8',timeout:180000,maxBuffer:65536});
 assert.equal(built.status,0,built.stderr);
 for(const [scenario,expected,calls] of [['success','started',1],['validation','not_sent',0],['console','not_sent',0],['running','not_sent',0],['error','uncertain',1],['wrong-process','uncertain',1],['clock','uncertain',0],['expired','not_sent',0],['shutdown',null,0]]) {
  const state=join(temporary,scenario);mkdirSync(state,{mode:0o700});
  const child=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'server',state,scenario],{stdio:'ignore'});children.push(child);
  await until(()=>existsSync(join(state,'session-control.json')));
  const invoke=(operation,id,service='mlx')=>{
   const result=spawnSync('/usr/bin/sandbox-exec',['-p',policy,binary,'client',state,service,operation,id],{encoding:'utf8',timeout:4000,maxBuffer:4096});
   assert.equal(result.status,0,result.stderr);return result.stdout.trim();
  };
  const id=randomUUID();assert.equal(invoke('launch',id),'uncertain');
  await until(()=>existsSync(join(state,'validation-entered')));
  assert.equal(invoke('lookup',id),'uncertain','Read-only validation blocked or prematurely acknowledged');
  if(scenario==='success')assert.equal(invoke('launch',randomUUID(),'orbstack'),'not_sent','Second validation queued instead of finite non-dispatch');
  if(scenario==='shutdown'){writeFileSync(join(state,'shutdown'),'stop');await until(()=>existsSync(join(state,'shutdown-observed')));}
  if(scenario==='expired'){
   await delay(10_100);
   assert.equal(invoke('lookup',id),'not_sent','Preparation timeout failed to revoke its future effect before worker completion');
   assert.equal(invoke('launch',randomUUID(),'orbstack'),'not_sent','Timed-out validator resource slot was released while still running');
  }
  writeFileSync(join(state,'release-validation'),'release');
  if(['success','console','running','error','wrong-process','clock'].includes(scenario))await until(()=>existsSync(join(state,'validation-observed')));
  if(calls===1)await until(()=>Number(readFileSync(join(state,'calls'),'utf8'))===1);
  if(expected==='uncertain'||expected===null)await delay(300);
  else await until(()=>invoke('lookup',id)===expected);
  if(expected!==null){assert.equal(invoke('lookup',id),expected);assert.equal(invoke('launch',id),expected,'Same-ID launch replayed after callback');}
  assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),calls,scenario+' dispatched an unexpected fake effect');
  child.kill('SIGTERM');await until(()=>exited(child));
 }
 for(const coldHelper of [false,true]) {
  const state=join(temporary,coldHelper?'recovery-cold':'recovery-known');mkdirSync(state,{mode:0o700});
  const start=async()=>{
   const child=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'server',state,'success'],{stdio:'ignore'});children.push(child);
   await until(()=>{try{return JSON.parse(readFileSync(join(state,'session-control.json'))).pid===child.pid;}catch{return false;}});return child;
  };
  let child=await start();
  const recover=phase=>{
   const result=spawnSync('/usr/bin/sandbox-exec',['-p',policy,binary,'recover',state,phase],{encoding:'utf8',timeout:5000,maxBuffer:4096});
   assert.equal(result.status,0,result.stderr);return result.stdout.trim();
  };
  assert.equal(recover('dispatch'),'launch/uncertain');
  assert.equal(recover('lookup'),'lookup/uncertain','Manager restart resent the native launch');
  writeFileSync(join(state,'release-validation'),'release');
  await until(()=>Number(readFileSync(join(state,'calls'),'utf8'))===1);
  if(coldHelper){child.kill('SIGTERM');await until(()=>exited(child));child=await start();}
  if(coldHelper){assert.equal(recover('lookup'),'lookup/uncertain');assert.equal(recover('lookup'),'lookup/uncertain');}
  else {await until(()=>recover('lookup')==='lookup/started');assert.equal(recover('lookup'),'none');}
  assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),1,'Durable recovery replayed an effect or lost its counter');
  child.kill('SIGTERM');await until(()=>exited(child));
 }
 console.log('PASS: actual async session driver, authenticated RPC, one validator/no queue, delayed/duplicate completion, validation/session/presence/expiry refusal, post-dispatch error/wrong-process uncertainty, shutdown/clock fencing and no replay; counter-only fake app API.');
 console.log('PASS: actual journal/controller/bounded sender across manager restart and cold helper generation; lookup-only intent reconciliation, no duplicate fake effect and independent native uncertainty retained.');
 const shown=spawnSync('swift',['build','--package-path',join(root,'platform/studio'),'--show-bin-path'],{encoding:'utf8',timeout:30000});assert.equal(shown.status,0);
 const cli=join(shown.stdout.trim(),'studioctl');
 for(const known of [false,true]) {
  const state=join(temporary,known?'manager-known':'manager-unknown');mkdirSync(state,{mode:0o700});
  const helper=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'server',state,'success'],{stdio:'ignore'});children.push(helper);
  await until(()=>existsSync(join(state,'session-control.json')));
  const startManager=()=>{
   const child=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'manager',state,known?'known':'unknown'],{stdio:'ignore'});children.push(child);return child;
  };
  let manager=startManager();
  const status=()=>{
   const result=spawnSync(cli,['--state',state,'status'],{encoding:'utf8',timeout:1500,maxBuffer:65536});
   return result.status===0 ? JSON.parse(result.stdout):null;
  };
  await until(()=>status()?.state==='ready');
  if(known){
   await until(()=>existsSync(join(state,'validation-entered')));
   const live=status();assert.equal(live.services.mlx.observed,'starting');assert.equal(live.native_activity,'unsupported');
   assert.equal(live.sandbox_admission,'disabled');
   writeFileSync(join(state,'release-validation'),'release');
   await until(()=>status()?.services.mlx.observed==='ready');
   assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),1);
   manager.kill('SIGTERM');await until(()=>exited(manager));manager=startManager();
   await until(()=>{const value=status();return value?.state==='ready'&&value.services.mlx.observed==='ready';});
   await delay(2300); // Cross another recovery cadence, not just startup.
   assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),1,'Full manager restart replayed native startup');
  }else{
   await delay(2300);assert.equal(status().services.mlx.observed,'unknown');
   assert.equal(existsSync(join(state,'validation-entered')),false,'Missing observation authorized a native effect');
   assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),0);
  }
  manager.kill('SIGTERM');await until(()=>exited(manager));helper.kill('SIGTERM');await until(()=>exited(helper));
 }
 console.log('PASS: real manager loop drives bounded recovery from trusted synthetic absence, preserves heartbeat/status, reports starting→ready and refuses unknown sources; counter-only app adapter, production issuer absent.');
}finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(temporary,{recursive:true,force:true});
}
