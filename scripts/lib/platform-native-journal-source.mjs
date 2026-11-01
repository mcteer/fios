// Private source-request/journal correlation only. No native admission issuer,
// model transport, production manager composition or terminality operation.
import assert from 'node:assert/strict';
import {spawn,spawnSync,execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,readdirSync,lstatSync,realpathSync,chmodSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
export function nativeJournalInputs(root){
 const core='platform/studio/Sources/StudioCore';
 const names=[...readdirSync(path.join(root,core)).filter(n=>n.endsWith('.swift')).sort().map(n=>core+'/'+n),
  'platform/studio/Sources/CSQLite/shim.h','platform/studio/Sources/CSQLite/module.modulemap',
  'platform/studio/Tests/StudioCoreTests/NativeJournalSource.swift.fixture',
  'scripts/lib/platform-native-journal-source.mjs','tests/fixtures/platform/native-journal-review.sb'];
 assert(names.length<=160);
 return Object.fromEntries(names.map(name=>[name,hash(readFileSync(path.join(root,name)))]));
}
export function buildNativeJournalObserver(root,parent,nonce){
 const inputs=nativeJournalInputs(root),fixture=path.join(root,'platform/studio/Tests/StudioCoreTests/NativeJournalSource.swift.fixture');
 const source=path.join(parent,'journal-source-'+nonce+'.swift'),binary=path.join(parent,'journal-observer-'+nonce);
 writeFileSync(source,readFileSync(fixture),{flag:'wx',mode:0o400});
 execFileSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',path.join(root,'platform/studio/Sources/CSQLite'),
  ...Object.keys(inputs).filter(n=>n.startsWith('platform/studio/Sources/StudioCore/')&&n.endsWith('.swift')).map(n=>path.join(root,n)),source,'-o',binary],
  {timeout:180000,maxBuffer:2<<20,stdio:'pipe'});
 chmodSync(binary,0o500);assert.deepEqual(nativeJournalInputs(root),inputs);assert.deepEqual(readFileSync(source),readFileSync(fixture));
 return {binary,sha256:hash(readFileSync(binary))};
}
export function verifyNativeJournalObserver(value,parent){
 assert(value&&Object.keys(value).sort().join(',')==='binary,sha256');
 assert(path.dirname(value.binary)===parent&&realpathSync(value.binary)===value.binary);
 const info=lstatSync(value.binary);
 assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.uid===process.getuid()&&(info.mode&0o7777)===0o500&&info.size>0&&info.size<=32<<20);
 assert.equal(hash(readFileSync(value.binary)),value.sha256);
}
export async function startNativeJournalObserver({root,plan,parent,home,native,endpointHash,profileHash,job,observeProcess,memoryLimit}){
 verifyNativeJournalObserver(plan.journal_observer,parent);
 const binary=plan.journal_observer.binary,state=path.join(home,'journal'),socket=path.join(home,'.fios-native-control/control.sock');
 const profile=path.join(root,'tests/fixtures/platform/native-journal-review.sb');
 const prefix=['-D','FIOS_JOURNAL_STATE='+home,'-D','FIOS_JOURNAL_BINARY='+binary,'-f',profile,binary];
 const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:path.join(home,'tmp'),LANG:'C',LC_ALL:'C'}; // No model/gateway credential.
 const child=spawn('/usr/bin/sandbox-exec',[...prefix,'--observe',state,socket,native.binary,native.sha256,String(native.pid),endpointHash,profileHash,job],
  {env,cwd:home,stdio:['pipe','pipe','pipe']});
 const ended=()=>child.exitCode!==null||child.signalCode!==null;
 const events=new Map();let buffer='',bytes=0,error,original,peakResident=0,peakFootprint=0,stopped;
 child.once('error',()=>{error=Error('Journal observer launch failed');});
 child.stdin.on('error',()=>{error??=Error('Journal observer pipe failed');});
 child.stderr.on('data',part=>{bytes+=part.length;if(bytes>32768)error??=Error('Journal observer output limit');});
 child.stdout.on('data',part=>{
  try{
   bytes+=part.length;assert(bytes<=32768);buffer+=part.toString('utf8');assert(buffer.length<=8192);
   let end;while((end=buffer.indexOf('\n'))>=0){
    const value=JSON.parse(buffer.slice(0,end));buffer=buffer.slice(end+1);
    assert(['ready','dispatched','stopped'].includes(value.event)&&value.native_authority===false&&!events.has(value.event));events.set(value.event,value);
   }
  }catch{error??=Error('Journal observer metadata refused');}
 });
 function sample(){
  const value=observeProcess(child.pid);
  assert(value.uid===process.getuid());if(original)assert.equal(value.start,original.start);else original=value;
  peakResident=Math.max(peakResident,value.resident);peakFootprint=Math.max(peakFootprint,value.footprint);
  assert(Math.max(peakResident,peakFootprint)<=memoryLimit,'Journal observer resource limit');return value;
 }
 function signal(signal){
  if(ended()||!original)return;
  try{const current=observeProcess(child.pid);if(current.start===original.start&&current.uid===original.uid)child.kill(signal);}catch{}
 }
 async function wait(name,deadline){
  while(performance.now()<deadline){if(error)throw error;if(events.has(name))return events.get(name);assert(!ended(),'Journal observer exited');await delay(10);}
  throw Error('Journal observer deadline');
 }
 let ready;
 async function stop({expectLive,deadline}){
  if(stopped)return stopped;
  stopped=(async()=>{
   if(!ended())child.stdin.end('stop\n');
   const graceful=Math.min(deadline-500,performance.now()+2200);
   while(!ended()&&performance.now()<graceful)await delay(10);
   if(!ended()){signal('SIGTERM');const term=Math.min(deadline-250,performance.now()+250);while(!ended()&&performance.now()<term)await delay(10);}
   if(!ended()){signal('SIGKILL');while(!ended()&&performance.now()<deadline)await delay(10);}
   if(!ended()){child.unref();child.stdin.destroy();child.stdout.destroy();child.stderr.destroy();throw Error('Journal observer not reaped; retain state');}
   assert(!error&&child.exitCode===0&&events.get('stopped')?.uncertainty_retained===true,'Journal observer did not stop normally');
   verifyNativeJournalObserver(plan.journal_observer,parent);
   const result=spawnSync('/usr/bin/sandbox-exec',[...prefix,'--inspect',state,job,ready.correlation_id,ready.native_instance,ready.scope_sha256,expectLive?'1':'0'],
    {env,cwd:home,encoding:'utf8',timeout:2000,maxBuffer:16384});
   assert.equal(result.status,0,'Stopped journal correlation inspection failed; retain private state');
   verifyNativeJournalObserver(plan.journal_observer,parent);
   const receipt=JSON.parse(result.stdout.trim());
   assert(receipt.source_fixture_only===true&&receipt.scope_correlated===true&&receipt.inference_state==='uncertain'&&receipt.native_authority===false);
   if(expectLive)assert(receipt.actual_request_root_observed===true);
   return {...receipt,observer_reaped:true,peak_resident:peakResident,peak_footprint:peakFootprint,production_admission_tested:false,platform_dispatch_tested:false,pydantic_worker_tested:false,proof_scope:'administrative_source_request_only'};
  })();return stopped;
 }
 try{
  const identityUntil=performance.now()+2000;
  while(!original&&!ended()&&performance.now()<identityUntil){try{sample();}catch(problem){if(original)throw problem;await delay(10);}}
  assert(original,'Journal observer identity unavailable');
  ready=await wait('ready',performance.now()+3000);
  assert(ready.job===job&&/^[a-f0-9]{64}$/.test(ready.correlation_id)&&/^[a-f0-9]{32}$/.test(ready.native_instance)&&/^[a-f0-9]{64}$/.test(ready.scope_sha256));
  return {ready,async dispatch(){assert(!events.has('dispatched'));child.stdin.write('attempt\n');await wait('dispatched',performance.now()+3000);},
   monitor(){
    if(error)throw error;
    // stop() owns bounded exit/reaping and stopped-journal inspection from
    // before its first shutdown effect. A missing live process during that
    // operation cannot be mistaken for an active-phase identity failure.
    if(stopped)return;
    assert(!ended(),'Journal observer exited before requested stop');sample();
   },stop};
 }catch(problem){
  if(!ended()){signal('SIGTERM');const end=performance.now()+500;while(!ended()&&performance.now()<end)await delay(10);if(!ended())signal('SIGKILL');const killed=performance.now()+1000;while(!ended()&&performance.now()<killed)await delay(10);}
  if(!ended()){child.unref();child.stdin.destroy();child.stdout.destroy();child.stderr.destroy();throw Error('Journal observer startup failed with unreaped child; retain state');}
  throw problem;
 }
}
