#!/usr/bin/env node
// Actual private native server + existing supervisor/manager composition.
// Empty catalog, synthetic reservations/absence/loading/failure overlays only.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {createServer} from 'node:net';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,copyFileSync,mkdirSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
const review=verifyNativeReview(args[2],args[4]),root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-serving-runtime-native-');
const hash=b=>createHash('sha256').update(b).digest('hex');
const core=join(root,'platform/studio/Sources/StudioCore'),name='MLXServingProcessRuntime.swift';
const inputs=Object.fromEntries(readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>[n,readFileSync(join(core,n))]));
function verifyCore(){
 assert.deepEqual(readdirSync(core).filter(n=>n.endsWith('.swift')).sort(),Object.keys(inputs));
 for(const [name,bytes] of Object.entries(inputs))assert(bytes.equals(readFileSync(join(core,name))));
}
const fixture=readFileSync(join(root,'platform/studio/Tests/NativeFixtures/NativeSupervisedServer.swift.fixture'));
const unit=join(directory,'RuntimeFixture.swift');writeFileSync(unit,Buffer.concat([inputs[name],Buffer.from('\n'),fixture]),{mode:0o600});
function run(program,args,timeout=120000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert(!r.error&&!r.signal,JSON.stringify({error:r.error?.code,signal:r.signal,directory}));assert.equal(r.status,0,r.stderr);return r.stdout;}
async function until(check,ms=10000){const end=Date.now()+ms;while(Date.now()<end){const value=check();if(value)return value;await delay(50);}throw Error('Finite native supervisor condition deadline; retained private review '+directory);}
console.log(JSON.stringify({directory,model_request_budget:0,synthetic_reservations:true,installed:false}));
for(const mode of ['debug','release']){
 const binary=join(directory,mode);
 run('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors',...(mode==='release'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...Object.keys(inputs).filter(n=>n!==name).map(n=>join(core,n)),unit,'-o',binary]);
 verifyCore();
 const listener=createServer();await new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(0,'127.0.0.1',resolve);});const port=listener.address().port;await new Promise(resolve=>listener.close(resolve));
 const policy=`(version 1)(allow default)(deny network*)(allow network* (local unix-socket)(remote unix-socket)(local ip "localhost:${port}")(remote ip "localhost:${port}"))`;
 const custodyState=mkdtempSync('/private/tmp/f9-mlx-supervisor-'),managerDirectory=join(directory,mode+'-custody-manager');
 mkdirSync(join(custodyState,'models'),{mode:0o700});mkdirSync(managerDirectory,{mode:0o700});const managerImage=join(managerDirectory,'studio-manager');copyFileSync(binary,managerImage);
 const custodyLog=openSync(join(custodyState,'fixture-supervisor.log'),'wx',0o600);
 const custodian=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'custody-supervisor',review.binary,hash(readFileSync(review.binary)),custodyState,hash(readFileSync(binary)),managerImage,String(port)],{stdio:['ignore',custodyLog,custodyLog]});closeSync(custodyLog);
 const custodyExited=()=>custodian.exitCode!==null||custodian.signalCode!==null;
 function custodyStatus(){const r=spawnSync(binary,['observe',custodyState],{encoding:'utf8',timeout:2500});const s=r.status===0?JSON.parse(r.stdout):null;if(s)writeFileSync(join(custodyState,'last-status.json'),JSON.stringify(s)+'\n',{mode:0o600});return s;}
 function custodyJSON(name){try{return JSON.parse(readFileSync(join(custodyState,name),'utf8'));}catch{return null;}}
 try {
  const first=await until(()=>{assert(!custodyExited());const s=custodyStatus(),mlx=s?.services?.mlx;return mlx?.observed==='ready'&&!mlx.launch_pending?s:null;},14000);
  assert.equal(first.unresolved_requests,1);assert.equal(first.services.mlx.recovery.starts_in_window,1);
  const original=custodyJSON('fixture-native-health.json'),before=custodyJSON('progress.json');assert.equal(original.state,'present');assert(original.pid>1);assert(original.launch_id);
  writeFileSync(join(custodyState,'fixture-exit-request'),'exit exactly one private manager',{mode:0o600,flag:'wx'});
  const second=await until(()=>{assert(!custodyExited());const progress=custodyJSON('progress.json'),supervisor=custodyJSON('supervisor.json');if(progress?.pid===before.pid||supervisor?.starts!==2)return null;const s=custodyStatus();return s?.services?.mlx?.observed==='ready'&&!s.services.mlx.launch_pending?s:null;},14000);
  const retained=custodyJSON('fixture-native-health.json');assert.equal(retained.pid,original.pid);assert.equal(retained.process_start,original.process_start);assert.equal(retained.launch_id,original.launch_id);
  assert.equal(second.unresolved_requests,1);assert.equal(second.services.mlx.recovery.starts_in_window,1);assert.equal(custodyJSON('supervisor.json').state,'running');
  writeFileSync(join(custodyState,'fixture-loading'),'synthetic loading overlay',{mode:0o600,flag:'wx'});
  await until(()=>{const s=custodyStatus();return s?.services?.mlx?.observed==='starting'&&!s.services.mlx.launch_pending&&!s.services.mlx.stop_pending;},6000);
  await delay(4200);assert.equal(custodyStatus().services.mlx.recovery.starts_in_window,1);
  assert.equal(custodyJSON('fixture-native-health.json').pid,original.pid);
  unlinkSync(join(custodyState,'fixture-loading'));await until(()=>custodyStatus()?.services?.mlx?.observed==='ready');
  writeFileSync(join(custodyState,'fixture-unavailable'),'unavailable original private identity',{mode:0o600,flag:'wx'});
  const recovered=await until(()=>{assert(!custodyExited());const s=custodyStatus(),mlx=s?.services?.mlx;return mlx?.observed==='ready'&&!mlx.stop_pending&&!mlx.launch_pending&&mlx.recovery.starts_in_window===2?s:null;},18000);
  const replacement=custodyJSON('fixture-native-health.json');assert(replacement.pid!==original.pid||replacement.process_start!==original.process_start);assert.notEqual(replacement.launch_id,original.launch_id);assert.equal(recovered.unresolved_requests,1);
  const requested=JSON.parse(run(binary,['control',custodyState,'stopped'],2500));assert.equal(requested.applied,false);
  const stopped=await until(()=>{assert(!custodyExited());const s=custodyStatus(),mlx=s?.services?.mlx;return mlx?.observed==='stopped'&&!mlx.stop_pending?s:null;},14000);
  assert.equal(stopped.unresolved_requests,1);assert.equal(stopped.services.mlx.desired,'stopped');
  custodian.kill('SIGTERM');await until(custodyExited,5000);assert.equal(custodian.exitCode,0);
  assert.deepEqual(readdirSync(join(custodyState,'models')),[]);
  assert.deepEqual(custodyJSON('custody-supervisor-receipt.json'),{start_validations:2,stop_validations:2,uncertain:1,native_authority:false});
  writeFileSync(join(directory,mode+'-custody-supervisor.json'),JSON.stringify({first,second,recovered,stopped,original,replacement,state:custodyState,identity:'actual_empty_model_native_server',health:'actual_kernel_listener_and_GET',readiness_and_reservations:'synthetic',native_authority:false})+'\n',{mode:0o600});
 }catch(error){console.error('RETAINED actual supervisor custody fixture:',custodyState);throw error;}finally{
  if(!custodyExited()){custodian.kill('SIGTERM');try{await until(custodyExited,4000);}catch{custodian.kill('SIGKILL');await until(custodyExited,3000);}}
 }
}
verifyCore();
assert(fixture.equals(readFileSync(join(root,'platform/studio/Tests/NativeFixtures/NativeSupervisedServer.swift.fixture'))));
assert.deepEqual(verifyNativeReview(args[2],args[4]),review);
const receipt={ok:true,directory,review_sha256:args[4],provenance_scope:'all_current_Core_Swift_files_and_fixture_not_whole_repository',core_inputs_sha256:Object.fromEntries(Object.entries(inputs).map(([name,bytes])=>[name,hash(bytes)])),fixture_sha256:hash(fixture),modes:['debug','release'],native_children:4,actual_supervisors:2,actual_managers:4,manager_replacements:2,real_listener_health:true,synthetic_readiness_and_reservations:true,model_posts:0,native_authority:false,installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(receipt));
